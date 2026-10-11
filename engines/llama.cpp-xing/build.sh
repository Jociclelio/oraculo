#!/usr/bin/env bash
# Build da engine Docker dedicada do fork shuxiaoqiong do llama.cpp (Xing4.0).
#
# REGRA DURA: NUNCA usar imagem stock para GGUFs Xing4.0 (arquitetura
# `xing4_0`) — o suporte vive no PR ggml-org#29012, ainda não mergeado.
#
# Uso: ./engines/llama.cpp-xing/build.sh
set -euo pipefail
cd "$(dirname "$0")"

# Deve espelhar o ARG XING_COMMIT do Dockerfile (commit pinado, nunca HEAD).
XING_COMMIT="8c379195a369cc3c6627d0eeb3e5060e2d160cd1"
XING_COMMIT_SHORT="8c379195a"
IMAGE="llama.cpp-xing"

docker build \
  --build-arg XING_COMMIT="${XING_COMMIT}" \
  -t "${IMAGE}:latest" \
  -t "${IMAGE}:${XING_COMMIT_SHORT}" \
  .

echo
echo "=== Imagens geradas ==="
docker images "${IMAGE}" --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'

echo
echo "=== Sanity check (sem GPU necessária para --version) ==="
docker run --rm "${IMAGE}:latest" llama-server --version
