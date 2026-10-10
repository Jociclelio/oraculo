#!/usr/bin/env bash
# Build da engine Docker dedicada do fork PrismML do llama.cpp (Bonsai 2).
#
# REGRA DURA do fork (ver /home/jocic/bonsai-llm/AGENTS.md): NUNCA usar imagem
# stock para GGUFs Bonsai (PQ2_0/PTQ1_0) — kernels ternários + Hadamard são
# exclusivos do fork PrismML.
#
# Uso: ./engines/llama.cpp-prismml/build.sh
set -euo pipefail
cd "$(dirname "$0")"

# Deve espelhar o ARG PRISMML_COMMIT do Dockerfile (commit pinado, nunca HEAD).
PRISMML_COMMIT="84445367fbaf79c00ff64bc93a0689cdb3eee54d"
PRISMML_COMMIT_SHORT="84445367f"
IMAGE="llama.cpp-prismml"

docker build \
  --build-arg PRISMML_COMMIT="${PRISMML_COMMIT}" \
  -t "${IMAGE}:latest" \
  -t "${IMAGE}:${PRISMML_COMMIT_SHORT}" \
  .

echo
echo "=== Imagens geradas ==="
docker images "${IMAGE}" --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'

echo
echo "=== Sanity check (sem GPU necessária para --version) ==="
docker run --rm "${IMAGE}:latest" llama-server --version
