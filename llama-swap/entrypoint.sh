#!/bin/sh
# entrypoint.sh — wrapper do container llama-swap (docker-compose.yml).
#
# Rodar o llama-swap em container tem uma consequência: os containers de
# modelo (ls-*) que ele dispara são IRMÃOS, não filhos — se o proxy morre,
# eles sobrevivem como órfãos retendo VRAM e bloqueiam a próxima carga com
# "container name /ls-<Modelo> is already in use".
# Com restart: unless-stopped o Docker religa o proxy sozinho (até no boot),
# então a limpeza precisa acontecer AQUI, antes de subir o servidor — o
# manage.sh não participa desse caminho.
#
# O `exec` mantém o llama-swap como PID 1 do container, para que SIGTERM do
# `docker stop` chegue nele (shutdown limpo, sem precisar de SIGKILL).

set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LISTEN="${LLAMA_SWAP_LISTEN:-127.0.0.1:8081}"
CONFIG="$REPO_DIR/llama-swap/config.yaml"

for c in $(docker ps -a --format '{{.Names}}' 2>/dev/null | grep '^ls-'); do
  echo "llama-swap: removendo container de modelo orfao $c"
  docker rm -f "$c" >/dev/null 2>&1 || true
done

exec "$REPO_DIR/bin/llama-swap" -listen "$LISTEN" -config "$CONFIG"
