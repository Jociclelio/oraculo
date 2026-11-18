#!/bin/sh
# Entrypoint do container Strata para entries do llama-swap (oraculo).
#
# Por que não usar o entrypoint oficial da imagem: ele força --access lan e
# uma API key obrigatória (o llama-swap não injeta Authorization no upstream),
# e fixa flags que não queremos. Este wrapper replica o que o oficial faz de
# essencial — `strata launch --no-tui` DAEMONIZA o servidor e RETORNA, então
# alguém precisa manter o container vivo, monitorar o status e fazer o stop
# gracioso (drain + unload da VRAM) no SIGTERM do `docker stop`.
#
# Uso (ver entry Strata no config.yaml):
#   --entrypoint /bin/sh <imagem> /strata-entrypoint.sh <PORT> [flags extra do launch...]
set -u
PORT="${1:-8080}"; shift
DATA_DIR="${STRATA_DATA_DIR:-/data/Strata-data}"

STRATA=/usr/local/bin/strata
# o launch precisa receber SIGINT (é assim que ele interrompe download/carga
# limpo); um sh não-interativo ignora SIGINT em filhos &, então executa via
# python que restaura o handler padrão (mesmo truque do entrypoint oficial)
RESET_INT='import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])'
PYBIN=$(command -v python3 || echo /opt/strata/terminal/python/bin/python3.12)

stopping=""
launch_pid=""
on_term() {
  stopping=1
  echo "[strata-entry] stop pedido: drain + unload do modelo"
  if [ -n "$launch_pid" ] && kill -0 "$launch_pid" 2>/dev/null; then
    kill -INT "$launch_pid" 2>/dev/null
    i=0; while kill -0 "$launch_pid" 2>/dev/null && [ "$i" -lt 60 ]; do sleep 1; i=$((i+1)); done
    kill -TERM "$launch_pid" 2>/dev/null || true
  fi
  "$STRATA" launch --stop --data-dir "$DATA_DIR" >/dev/null 2>&1 || true
  exit 0
}
trap on_term TERM INT

echo "[strata-entry] strata launch --port $PORT (data-dir $DATA_DIR)"
"$PYBIN" -c "$RESET_INT" "$STRATA" launch --no-tui --yes \
  --access local --port "$PORT" --data-dir "$DATA_DIR" \
  --no-api-key "$@" &
launch_pid=$!
wait "$launch_pid"
rc=$?
launch_pid=""
[ -n "$stopping" ] && exit 0
if [ "$rc" -ne 0 ]; then
  echo "[strata-entry] strata launch falhou com código $rc"
  exit "$rc"
fi

# o launch daemonizou o servidor: mantém o container vivo enquanto ele servir
bad=0
while [ -z "$stopping" ]; do
  sleep 10 &
  wait $!
  [ -n "$stopping" ] && break
  if "$STRATA" launch --status --data-dir "$DATA_DIR" --output json 2>/dev/null | grep -q '"state": *"ready"'; then
    bad=0
  else
    bad=$((bad+1))
  fi
  if [ "$bad" -ge 3 ]; then
    echo "[strata-entry] servidor não está mais respondendo; encerrando"
    exit 1
  fi
done
exit 0
