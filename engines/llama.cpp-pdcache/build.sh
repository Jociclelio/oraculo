#!/usr/bin/env bash
# Build da engine Docker dedicada: llama.cpp STOCK + patch de prompt disk
# cache (porta manual do fork qqkzlm/llama-cpp-prompt-disk-cache para o
# master ggml-org).
#
# Motivação: regra 9 do AGENTS.md — o /slots save/restore do stock NÃO
# serializa context checkpoints em modelos híbridos/SWA (bug
# ggml-org/llama.cpp#28194). O patch escreve snapshots completos `.centry` em
# disco e restaura o prefixo no próximo request após o (re)start, sobrevivendo
# ao `docker rm -f` do llama-swap sem orquestração.
#
# POR QUE stock e não a imagem do fork: a linhagem `prism` tem prefill de MoE
# com experts na CPU 20x mais lento que o master (35 vs 800 tok/s medidos
# 2026-10-17 com -ncmoe 31) — ver comentário do Dockerfile.
#
# Uso: ./engines/llama.cpp-pdcache/build.sh
set -euo pipefail
cd "$(dirname "$0")"

# Deve espelhar o ARG STOCK_COMMIT do Dockerfile (commit pinado, nunca HEAD).
STOCK_COMMIT="5e03a1ff450cae37a774684de55d14fb48b1f90b"
STOCK_COMMIT_SHORT="5e03a1ff4"
IMAGE="llama.cpp-pdcache"

docker build \
  --build-arg STOCK_COMMIT="${STOCK_COMMIT}" \
  -t "${IMAGE}:latest" \
  -t "${IMAGE}:${STOCK_COMMIT_SHORT}" \
  .

echo
echo "=== Imagens geradas ==="
docker images "${IMAGE}" --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'

echo
echo "=== Sanity check (sem GPU necessária para --version) ==="
docker run --rm --entrypoint /bin/bash "${IMAGE}:latest" -c "/usr/local/bin/llama-server --version 2>&1 | tail -1"

echo
echo "=== Sanity check das flags do cache de disco ==="
docker run --rm --entrypoint /bin/bash "${IMAGE}:latest" -c "/usr/local/bin/llama-server --help 2>&1 | grep -o -- '--prompt-cache-disk[a-z-]*\|--slot-save-path' | sort -u"
