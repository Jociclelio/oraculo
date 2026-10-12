#!/bin/bash
# manage.sh — gerencia o llama-swap (proxy único em 127.0.0.1:8081) em background.
# Substitui o antigo ciclo docker compose do serviço llama-cpp.

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

do_start() {
  if is_running; then
    echo "llama-swap já está em execução (PID $(cat "$PIDFILE"))."
    echo "Use '$0 stop' antes de iniciar novamente."
    exit 0
  fi

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

  # Segurança: só encerrar se o PID pertence ao llama-swap.
  if ! ps -p "$pid" -o comm= 2>/dev/null | grep -q "llama-swap"; then
    echo "Erro: PID $pid no pidfile não corresponde ao llama-swap." >&2
    echo "Remova $PIDFILE manualmente após verificar o processo." >&2
    exit 1
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
  echo "llama-swap parado."
}

do_unload() {
  # Remove os containers de modelo do llama-swap (ls-*) para liberar VRAM.
  # Útil antes de gerar imagens no ComfyUI quando o ttl de 5 min ainda não
  # descarregou o modelo (o llama-swap não tem unload manual; apontar o
  # request para outro modelo também força o swap).
  local names
  names=$(docker ps --format "{{.Names}}" | grep "^ls-" || true)
  if [ -z "$names" ]; then
    echo "Nenhum container de modelo (ls-*) em execução — VRAM já livre."
    return 0
  fi
  echo "$names" | while read -r c; do
    echo "Removendo $c..."
    docker rm -f "$c" >/dev/null
  done
  echo "Containers de modelo removidos; VRAM liberada."
}

do_status() {
  if is_running; then
    echo "llama-swap em execução (PID $(cat "$PIDFILE")), porta $PORT."
  else
    echo "llama-swap não está em execução."
    exit 1
  fi
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
  *)
    echo "Uso: $0 {start|stop|restart|status}"
    echo ""
    echo "  start    Inicia o llama-swap em background (pidfile + log em logs/)"
    echo "  stop     Encerra o processo via pidfile (SIGTERM, fallback SIGKILL)"
    echo "  restart  Para e inicia novamente"
    echo "  status   Mostra se o llama-swap está rodando"
  echo "  unload   Remove containers ls-* (libera VRAM p/ ComfyUI)"
    exit 1
    ;;
esac
