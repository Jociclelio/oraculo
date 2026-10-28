#!/usr/bin/env bash
# Build da engine Docker "bonsai-ada" (fork llama.cpp-ada-ternary — patch
# stack do projeto bonsai-ada-surgery sobre o PrismML, 71 patches).
#
# Uso: ./engines/llama.cpp-bonsai-ada/build.sh
#
# REGRA DURA (herdada do PrismML): NUNCA usar imagem stock para GGUFs Bonsai 2
# (PTQ1_0) — kernels ternários são exclusivos do fork. Esta imagem é o
# supersetch da prismml (mesma base adfffbe + patches 0001-0071).
set -euo pipefail
cd "$(dirname "$0")"

# Deve espelhar o ARG ADA_COMMIT do Dockerfile (commit pinado, nunca HEAD).
ADA_COMMIT="2cadbfb64026b77293a76cf1a2d16e1aefeee45d"
ADA_COMMIT_SHORT="2cadbfb6"
IMAGE="llama.cpp-bonsai-ada"

docker build \
  --build-arg ADA_COMMIT="${ADA_COMMIT}" \
  -t "${IMAGE}:latest" \
  -t "${IMAGE}:${ADA_COMMIT_SHORT}" \
  .

echo
echo "=== Imagens geradas ==="
docker images "${IMAGE}" --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'

echo
echo "=== Sanity check (sem GPU necessária para --version) ==="
docker run --rm "${IMAGE}:latest" llama-server --version
