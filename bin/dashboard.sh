#!/bin/bash
# dashboard.sh — painel de terminal do oraculo (one-shot; use com watch)
#
#   watch -n 2 ./bin/dashboard.sh
#
# Mostra: modelo ativo (container ls-* do llama-swap), uptime, contexto,
# últimas taxas de prefill/decode medidas pelo llama-server (docker logs)
# e uso de VRAM da GPU (inclui desktop/jogos — GPU compartilhada).
#
# Sem modelo carregado (ttl: 300 descarregou ou proxy parado), indica idle.

ORACULO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ORACULO_DIR/llama-swap/config.yaml"
PIDFILE="$ORACULO_DIR/logs/llama-swap.pid"

# --- proxy -----------------------------------------------------------------
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    PROXY="no ar (127.0.0.1:8081)"
else
    PROXY="PARADO — ./manage.sh start"
fi

# --- modelo ativo ----------------------------------------------------------
CONTAINER="$(docker ps --format '{{.Names}}' 2>/dev/null | grep '^ls-' | head -n1)"

echo "oraculo — $(date '+%H:%M:%S')"
echo "proxy llama-swap : $PROXY"

if [ -z "$CONTAINER" ]; then
    echo "modelo ativo     : — (nenhum carregado; idle ou descarregado pelo ttl 300s)"
    echo
    echo "dica: o primeiro request em http://127.0.0.1:8081/v1/chat/completions"
    echo "      dispara a carga do modelo apontado no campo \"model\"."
    exit 0
fi

MODEL="${CONTAINER#ls-}"
STATUS="$(docker ps --filter "name=^${CONTAINER}\$" --format '{{.Status}}')"

# contexto (-c) do entry no config.yaml (fonte da verdade)
CTX="$(awk -v m="$MODEL" '
    index($0, "  " m ":") == 1 {blk=1; next}
    blk && /^[A-Za-z]/ {exit}
    blk && match($0, /-c [0-9]+/) {print substr($0, RSTART+3, RLENGTH-3); exit}
' "$CONFIG")"

echo "modelo ativo     : $MODEL  ($STATUS, ctx ${CTX:-?})"

# --- GPU -------------------------------------------------------------------
GPU="$(nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null)"
if [ -n "$GPU" ]; then
    IFS=', ' read -r VUSED VTOT VUTIL <<< "$GPU"
    echo "GPU              : ${VUSED} / ${VTOT} MiB  (util ${VUTIL}%)"
fi

# --- últimas taxas (print_timing do llama-server) --------------------------
LOG="$(docker logs --tail 300 "$CONTAINER" 2>&1)"

PREFILL="$(echo "$LOG" | grep 'prompt eval time =' | tail -n1)"
DECODE="$(echo "$LOG" | grep 'eval time =' | grep -v 'prompt eval' | tail -n1)"

# captura: task, ms total, tokens, tok/s
parse() {
    sed -nE 's/.*task ([0-9]+) \| .* time = +([0-9.]+) ms \/ +([0-9]+) tokens \(.+?, +([0-9.]+) tokens per second\)/\1 \2 \3 \4/p'
}

if [ -n "$PREFILL" ]; then
    read -r TASK PMS PTOK PRATE <<< "$(echo "$PREFILL" | parse)"
    echo
    echo "última medição (task $TASK)"
    printf '  prefill : %8s tok/s  (%s tok em %ss)\n' "$PRATE" "$PTOK" "$(awk -v v="$PMS" 'BEGIN{printf "%.1f", v/1000}')"
else
    echo
    echo "prefill : — (nenhum request processado desde a carga)"
fi

if [ -n "$DECODE" ]; then
    read -r TASK2 DMS DTOK DRATE <<< "$(echo "$DECODE" | parse)"
    printf '  decode  : %8s tok/s  (%s tok em %ss)\n' "$DRATE" "$DTOK" "$(awk -v v="$DMS" 'BEGIN{printf "%.1f", v/1000}')"
else
    echo "  decode  : —"
fi
