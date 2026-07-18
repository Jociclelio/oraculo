#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

stop_current_llama() {
  echo "Parando container llama-cpp atual..."
  if [ "$(docker ps -q -f name=llama-cpp)" ]; then
    docker stop llama-cpp
  fi
  if [ "$(docker ps -aq -f name=llama-cpp)" ]; then
    docker rm llama-cpp
  fi
}

case "$1" in
  start)
    stop_current_llama
    echo "Iniciando llama-cpp..."
    docker compose up -d llama-cpp
    ;;
  stop)
    echo "Parando tudo..."
    docker compose down
    ;;
  *)
    echo "Uso: $0 {start|stop}"
    echo ""
    echo "  start   Inicia o servidor llama-cpp (inferência GPU)"
    echo "  stop    Para todos os containers"
    exit 1
    ;;
esac
