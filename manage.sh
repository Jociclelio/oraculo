#!/bin/bash
# manage.sh — gerencia a stack inteira:
#   1. llama-swap (proxy de modelos em 127.0.0.1:8081, processo de HOST)
#   2. serviços auxiliares via docker compose (webui, terminal, searxng,
#      comfyui, mcp-playwright, mcp-memory, openwa + docker-proxy)
#
# start = llama-swap + docker compose up -d | stop = llama-swap + compose down

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BIN="bin/llama-swap"
CONFIG="llama-swap/config.yaml"
LOGDIR="logs"
PIDFILE="$LOGDIR/llama-swap.pid"
LOGFILE="$LOGDIR/llama-swap.log"
PORT=8081
STOP_TIMEOUT=10

is_running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

# --- serviços auxiliares (docker compose) ---------------------------------
# O compose tem restart policy própria, mas "desligar tudo" exige down: com
# restart: always/unless-stopped os containers voltariam sozinhos no boot.
compose_any_up() {
  [ -n "$(docker compose ps -q 2>/dev/null)" ]
}

compose_up() {
  echo "Subindo serviços auxiliares (docker compose up -d)..."
  if ! docker compose up -d; then
    echo "Erro: docker compose up -d falhou." >&2
    return 1
  fi
  docker compose ps
}

compose_down() {
  if ! compose_any_up; then
    echo "Serviços auxiliares já estão parados."
    return 0
  fi
  echo "Parando serviços auxiliares (docker compose down)..."
  docker compose down
}

do_start() {
  if is_running; then
    echo "llama-swap já está em execução (PID $(cat "$PIDFILE"))."
  else
    start_llama_swap
  fi
  compose_up
}

start_llama_swap() {

  # Pidfile órfão (processo já morreu) — limpar antes de iniciar.
  rm -f "$PIDFILE"

  if [ ! -x "$BIN" ]; then
    echo "Erro: binário não encontrado em $BIN." >&2
    echo "Execute ./llama-swap/install.sh primeiro." >&2
    exit 1
  fi

  if [ ! -f "$CONFIG" ]; then
    echo "Erro: arquivo de configuração não encontrado: $CONFIG" >&2
    echo "O llama-swap é iniciado com '-config $CONFIG'; crie o arquivo" >&2
    echo "antes de iniciar (veja a task/config do plano llama-swap-multi-engine)." >&2
    exit 1
  fi

  mkdir -p "$LOGDIR"
  echo "Iniciando llama-swap em background (porta $PORT)..."
  # O endereço de escuta não vem do config.yaml — é controlado pela flag
  # -listen (o env LLAMA_SWAP_LISTEN não é honrado na v263). Fixado em
  # 127.0.0.1:$PORT, porta que a WebUI já usa em OAI_API_BASE=http://localhost:8081/v1.
  nohup "$BIN" -listen "127.0.0.1:$PORT" -config "$CONFIG" >>"$LOGFILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PIDFILE"

  # Aguardar a porta $PORT responder antes de reportar sucesso. O sucesso só
  # vale se for o NOSSO processo (PID vivo) — outra coisa pode ocupar a porta.
  local i
  for i in $(seq 1 30); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "Erro: llama-swap (PID $pid) morreu durante a inicialização." >&2
      echo "Últimas linhas de $LOGFILE:" >&2
      tail -n 15 "$LOGFILE" >&2 || true
      rm -f "$PIDFILE"
      exit 1
    fi
    if curl -fsS "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
      echo "llama-swap ativo: PID $pid, log em $LOGFILE."
      echo "API: http://127.0.0.1:$PORT/v1/models"
      return 0
    fi
    sleep 1
  done

  echo "Erro: porta $PORT não respondeu em 30 s (PID $pid ainda vivo)." >&2
  echo "Verifique o log em $LOGFILE." >&2
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
  names=$(docker ps --format "{{.Names}}" | grep "^ls-" || true)
  if [ -z "$names" ]; then
    return 0
  fi
  echo "$names" | while read -r c; do
    echo "Removendo container de modelo órfão/ativo $c..."
    docker rm -f "$c" >/dev/null
  done
}

stop_llama_swap() {
  if [ ! -f "$PIDFILE" ]; then
    echo "llama-swap não está rodando (pidfile ausente)."
    return 0
  fi

  local pid
  pid="$(cat "$PIDFILE")"

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "llama-swap não está rodando (PID $pid inativo; limpando pidfile)."
    rm -f "$PIDFILE"
    return 0
  fi

  # Segurança: só encerrar se o PID pertence ao llama-swap. Não impede o
  # compose down (desligar tudo continua funcionando).
  if ! ps -p "$pid" -o comm= 2>/dev/null | grep -q "llama-swap"; then
    echo "Aviso: PID $pid no pidfile não corresponde ao llama-swap; não será morto." >&2
    echo "Revise $PIDFILE manualmente." >&2
    return 0
  fi

  echo "Parando llama-swap (PID $pid)..."
  kill -TERM "$pid" 2>/dev/null || true

  local i
  for i in $(seq 1 "$STOP_TIMEOUT"); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done

  if kill -0 "$pid" 2>/dev/null; then
    echo "Processo não encerrou com SIGTERM; enviando SIGKILL..."
    kill -KILL "$pid" 2>/dev/null || true
  fi

  rm -f "$PIDFILE"
  # Também derruba containers de modelo: sem o proxy eles viram órfãos
  # retendo VRAM (ver comentário em do_stop). Cobre `swap stop/restart`.
  remove_model_containers
  echo "llama-swap parado."
}

do_unload() {
  # Libera a VRAM dos modelos LLM antes de gerar imagens no ComfyUI.
  # Preferência: GET /unload do llama-swap (síncrono, ~0,5 s; o gpu-shim do
  # ComfyUI chama o mesmo endpoint a cada request). Fallback: docker rm -f.
  if curl -fsS --max-time 60 "http://127.0.0.1:$PORT/unload" >/dev/null 2>&1; then
    echo "llama-swap descarregou os modelos; VRAM liberada."
    return 0
  fi
  if [ -z "$(docker ps --format "{{.Names}}" | grep "^ls-" || true)" ]; then
    echo "Nenhum container de modelo (ls-*) em execução — VRAM já livre."
    return 0
  fi
  remove_model_containers
  echo "Containers de modelo removidos; VRAM liberada."
}

do_status() {
  local rc=0
  if is_running; then
    echo "llama-swap em execução (PID $(cat "$PIDFILE")), porta $PORT."
  else
    echo "llama-swap não está em execução."
    rc=1
  fi
  echo ""
  echo "Serviços auxiliares (docker compose):"
  docker compose ps
  exit "$rc"
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
    do_unload
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
  *)
    echo "Uso: $0 {start|stop|restart|status|unload|swap|services}"
    echo ""
    echo "  start            Inicia TUDO: llama-swap + docker compose up -d"
    echo "  stop             Desliga TUDO: llama-swap + docker compose down"
    echo "  restart          Para e inicia novamente (tudo)"
    echo "  status           llama-swap + docker compose ps"
    echo "  unload           Descarrega modelos ls-* (libera VRAM p/ ComfyUI)"
    echo "  swap <sub>       Só o llama-swap: start|stop|restart"
    echo "  services <sub>   Só o compose (webui/terminal/searxng/comfyui/mcp/openwa): start|stop"
    exit 1
    ;;
esac
