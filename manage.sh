#!/bin/bash
# manage.sh — gerencia a stack inteira (tudo em Docker):
#   1. llama-swap (proxy de modelos em 127.0.0.1:8081, container)
#   2. serviços auxiliares via docker compose (webui, terminal, searxng,
#      comfyui, mcp-playwright, mcp-memory, mcp-comfyui, openwa + docker-proxy)
#
# start = compose up -d (llama-swap + serviços) | stop = para tudo
# Os containers têm restart: always/unless-stopped, então o stack sobe
# SOZINHO no boot junto com o docker.service — este script é para controle
# manual (start/stop/restart, unload de VRAM, logs).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BIN="bin/llama-swap"
CONFIG="llama-swap/config.yaml"
SWAP_CONTAINER="llama-swap"
PORT=8081
STOP_TIMEOUT=10

# O llama-swap roda como container (docker-compose.yml). O binário é Go
# estático montado de bin/llama-swap via bind do repo em /home/jocic/oraculo.
is_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$SWAP_CONTAINER" 2>/dev/null)" = "true" ]
}

# --- serviços auxiliares (docker compose) ---------------------------------
# O compose tem restart policy própria, mas "desligar tudo" exige parar os
# containers: com restart: always/unless-stopped eles voltariam sozinhos no
# boot. O llama-swap também é um serviço do compose, mas tem controle fino
# próprio (`swap start|stop`) — por isso as listas abaixo o excluem.

# Serviços auxiliares que existem agora (running), sem llama-swap/hermes.
aux_services_up() {
  docker compose ps --services 2>/dev/null | grep -vx -e "$SWAP_CONTAINER" -e hermes || true
}

compose_up() {
  echo "Subindo o stack (docker compose up -d)..."
  if ! docker compose up -d; then
    echo "Erro: docker compose up -d falhou." >&2
    return 1
  fi
  docker compose ps
}

compose_down() {
  local svcs
  svcs="$(aux_services_up)"
  if [ -z "$svcs" ]; then
    echo "Serviços auxiliares já estão parados."
  else
    echo "Parando serviços auxiliares (docker compose stop)..."
    # shellcheck disable=SC2086
    docker compose stop $svcs
  fi
  # hermes fica fora do compose default (profile "hermes", gerenciado pelo
  # hermes-gate): o stop por lista não o alcança — parar explicitamente no
  # "tudo off"
  if [ "$(docker inspect -f '{{.State.Running}}' hermes 2>/dev/null)" = "true" ]; then
    echo "Parando hermes (gerenciado pelo hermes-gate)..."
    docker compose --profile hermes stop hermes
  fi
}

do_start() {
  start_llama_swap
  compose_up
}

start_llama_swap() {
  if [ ! -x "$BIN" ]; then
    echo "Erro: binário não encontrado em $BIN." >&2
    echo "Execute ./llama-swap/install.sh primeiro." >&2
    exit 1
  fi

  if [ ! -f "$CONFIG" ]; then
    echo "Erro: arquivo de configuração não encontrado: $CONFIG" >&2
    echo "O container llama-swap é iniciado com '-config /home/jocic/oraculo/llama-swap/config.yaml'." >&2
    exit 1
  fi

  if is_running; then
    echo "llama-swap já está em execução (container $SWAP_CONTAINER)."
  else
    echo "Subindo llama-swap (container $SWAP_CONTAINER, porta $PORT)..."
    if ! docker compose up -d "$SWAP_CONTAINER"; then
      echo "Erro: docker compose up -d $SWAP_CONTAINER falhou." >&2
      exit 1
    fi
  fi

  # Aguardar a porta responder: só então o proxy está realmente servindo
  # (o container pode estar "Up" antes de o listener abrir).
  local i
  for i in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
      echo "llama-swap ativo: container $SWAP_CONTAINER, log em 'docker logs -f $SWAP_CONTAINER'."
      echo "API: http://127.0.0.1:$PORT/v1/models"
      return 0
    fi
    # Se o container morreu (ex.: binário removido/corrompido), abortar já.
    if [ "$i" -ge 3 ] && ! is_running; then
      echo "Erro: container $SWAP_CONTAINER não está rodando." >&2
      echo "Últimas linhas do log:" >&2
      docker logs --tail 20 "$SWAP_CONTAINER" 2>&1 >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "Erro: porta $PORT não respondeu em 30 s (container $SWAP_CONTAINER)." >&2
  echo "Verifique: docker logs --tail 50 $SWAP_CONTAINER" >&2
  exit 1
}

do_stop() {
  stop_llama_swap
  compose_down
  # Os containers de modelo (ls-*) não pertencem ao compose: sem esta
  # limpeza eles sobrevivem ao restart como ÓRFÃOS (2026-10-14 — um Qwen de
  # 9,8 GB ficou residente, o proxy novo não o rastreava e toda carga nova
  # falhava com "upstream command exited prematurely" por falta de VRAM).
  remove_model_containers
}

# Remove containers de modelo (ls-*) órfãos ou ativos. Silencioso quando
# não há nenhum. Usado no stop (todo restart/stop) e como fallback no unload.
remove_model_containers() {
  local names
  # -a: pega também os parados (um container ls-* em Exited bloqueia a
  # próxima carga pelo nome, mesmo sem estar consumindo VRAM).
  names=$(docker ps -a --format "{{.Names}}" | grep "^ls-" || true)
  if [ -z "$names" ]; then
    return 0
  fi
  echo "$names" | while read -r c; do
    echo "Removendo container de modelo órfão/ativo $c..."
    docker rm -f "$c" >/dev/null
  done
}

stop_llama_swap() {
  if is_running; then
    echo "Parando llama-swap (container $SWAP_CONTAINER)..."
    docker compose stop -t "$STOP_TIMEOUT" "$SWAP_CONTAINER" >/dev/null || true
    echo "llama-swap parado."
  else
    echo "llama-swap não está em execução."
  fi

  # Também derruba containers de modelo: sem o proxy eles viram órfãos
  # retendo VRAM (ver comentário em do_stop). Cobre `swap stop/restart`.
  remove_model_containers
}

# Relatório de VRAM: total/usado/livre + processos compute ordenados por uso.
# Origem das medidas (2026-11-09, GPU idle): LLM ~10,4 GiB; ComfyUI 100-220
# MiB de contexto CUDA (piso que /free NÃO derruba); desktop
# (Hyprland+firefox+vesktop+terminais+ashell) ~540 MiB; reserva do driver
# ~320 MiB (só sai com `rmmod nvidia*`, isto é, sessão headless).
print_vram_report() {
  local total used free
  IFS=, read -r total used free < <(nvidia-smi --query-gpu=memory.total,memory.used,memory.free \
    --format=csv,noheader,nounits | head -1)
  total=${total// /}; used=${used// /}; free=${free// /}
  echo "VRAM: ${used} MiB usados / ${total} total — ${free} MiB livres"
  echo ""
  printf '  %-8s %10s  %s\n' PID MIB PROCESSO
  # pmon lista TODOS os processos da GPU (compute + gráficos). --query-compute-apps
  # omite Hyprland/browsers/terminais, que também consomem VRAM.
  local rows
  rows=$(nvidia-smi pmon -c 1 -s m 2>/dev/null \
    | awk '$1 ~ /^[0-9]+$/ {print $4, $2, $6}' | sort -rn)
  if [ -n "$rows" ]; then
    echo "$rows" | while read -r mib pid name; do
      printf '  %-8s %10s  %s\n' "$pid" "$mib" "$name"
    done
  else
    nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits \
      | sort -t, -k2 -rn \
      | while IFS=, read -r pid mib; do
          [ -n "$pid" ] || continue
          printf '  %-8s %10s  %s\n' "${pid// /}" "${mib// /}" \
            "$(ps -p "${pid// /}" -o comm= 2>/dev/null || echo '?')"
        done
  fi
}

do_vram() {
  print_vram_report
}

do_unload() {
  local hard="${1:-}"
  # Libera a VRAM dos modelos LLM antes de gerar imagens no ComfyUI.
  # Preferência: GET /unload do llama-swap (síncrono, ~0,5 s; o gpu-shim do
  # ComfyUI chama o mesmo endpoint a cada request). Fallback: docker rm -f.
  if curl -fsS --max-time 60 "http://127.0.0.1:$PORT/unload" >/dev/null 2>&1; then
    echo "llama-swap descarregou os modelos; VRAM liberada."
  elif [ -z "$(docker ps --format "{{.Names}}" | grep "^ls-" || true)" ]; then
    echo "Nenhum container de modelo (ls-*) em execução — VRAM já livre."
  else
    remove_model_containers
    echo "Containers de modelo removidos; VRAM liberada."
  fi

  [ "$hard" = "--hard" ] || return 0

  # --hard: derruba TAMBÉM o piso do ComfyUI. POST /free (com free_memory)
  # só devolve os pesos ao caching allocator — o contexto CUDA (~100-220
  # MiB) permanece; a única forma de zerar é matar o processo torch.
  echo ""
  echo "Modo --hard: parando o ComfyUI para liberar o contexto CUDA..."
  docker stop comfyui >/dev/null 2>&1 \
    && echo "ComfyUI parado (religar com: ./manage.sh services start)." \
    || echo "Aviso: ComfyUI já estava parado ou falhou ao parar."
  sleep 2
  echo ""
  print_vram_report
  echo ""
  echo "Restante não liberável em runtime: desktop (~540 MiB) + reserva do"
  echo "driver (~320 MiB). Teto prático sem o desktop: ~11,9 GiB de 12 GiB."
  echo "Para chegar lá, sair da sessão gráfica (TTY/SSH): systemctl isolate multi-user.target"
}

do_status() {
  local rc=0
  if is_running; then
    echo "llama-swap em execução (container $SWAP_CONTAINER), porta $PORT."
  else
    echo "llama-swap não está em execução."
    rc=1
  fi
  echo ""
  echo "Stack (docker compose ps):"
  docker compose ps
  exit "$rc"
}

do_logs() {
  # Logs do proxy em tempo real (o container escreve em stdout/stderr).
  docker logs -f --tail "${1:-200}" "$SWAP_CONTAINER" 2>&1
}

case "$1" in
  start)
    do_start
    ;;
  stop)
    do_stop
    ;;
  restart)
    do_stop
    do_start
    ;;
  status)
    do_status
    ;;
  unload)
    do_unload "$2"
    ;;
  vram)
    do_vram
    ;;
  swap)
    # Controle fino: só o llama-swap (não toca no compose).
    case "$2" in
      start)   start_llama_swap ;;
      stop)    stop_llama_swap ;;
      restart) stop_llama_swap; start_llama_swap ;;
      *) echo "Uso: $0 swap {start|stop|restart}" >&2; exit 1 ;;
    esac
    ;;
  services)
    # Controle fino: só os serviços auxiliares (não toca no llama-swap).
    case "$2" in
      start) compose_up ;;
      stop)  compose_down ;;
      *) echo "Uso: $0 services {start|stop}" >&2; exit 1 ;;
    esac
    ;;
  logs)
    do_logs "$2"
    ;;
  *)
    echo "Uso: $0 {start|stop|restart|status|unload|vram|logs|swap|services}"
    echo ""
    echo "  start            Inicia TUDO: llama-swap + docker compose up -d"
    echo "  stop             Desliga TUDO: llama-swap + serviços auxiliares"
    echo "  restart          Para e inicia novamente (tudo)"
    echo "  status           llama-swap + docker compose ps"
    echo "  unload           Descarrega modelos ls-* (libera VRAM p/ ComfyUI)"
    echo "  unload --hard    + para o ComfyUI (zera também o contexto CUDA ~150 MiB)"
    echo "  vram             Relatório de VRAM (total/usado/livre + processos)"
    echo "  logs [N]         Logs do llama-swap em tempo real (últimas N linhas)"
    echo "  swap <sub>       Só o llama-swap: start|stop|restart"
    echo "  services <sub>   Só o compose (webui/terminal/searxng/comfyui/mcp/openwa): start|stop"
    exit 1
    ;;
esac
