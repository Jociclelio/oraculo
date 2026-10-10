# Engine dedicada do fork PrismML do llama.cpp — necessária para os GGUFs
# Bonsai 2 (kernels ternários + Hadamard runtime).
#
# REGRA DURA (ver /home/jocic/bonsai-llm/AGENTS.md): NUNCA usar a imagem stock
# (ghcr.io/ggml-org/llama.cpp) para Bonsai 2 — ela recusa PQ2_0/PTQ1_0 ou carrega
# como Q2_0 legacy gerando lixo. Esta imagem pinada garante o isolamento do fork.
#
# Fonte: https://github.com/PrismML-Eng/llama.cpp (branch `prism`), commit PINADO
# (nunca origin/prism HEAD). Commit verificado no checkout local de referência
# /home/jocic/bonsai-llm/llama.cpp (branch `prism`).
FROM nvidia/cuda:13.4.2-devel-ubuntu24.04

ARG PRISMML_REPO="https://github.com/PrismML-Eng/llama.cpp"
ARG PRISMML_BRANCH="prism"
# Commit PINADO (tip de `prism` em 2026-10-10, conferido no checkout local).
ARG PRISMML_COMMIT="84445367fbaf79c00ff64bc93a0689cdb3eee54d"
# Alvo: RTX 3060 (Ampere) — mesma arquitetura do build nativo de referência.
ARG CUDA_ARCH="86"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git cmake build-essential libcurl4-openssl-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Clone shallow da branch `prism` com checkout forçado no commit pinado e
# verificação dura (o build falha se HEAD != commit pinado).
RUN git clone --depth 1 --branch "${PRISMML_BRANCH}" "${PRISMML_REPO}" . \
 && git fetch --depth 1 origin "${PRISMML_COMMIT}" \
 && git checkout --detach "${PRISMML_COMMIT}" \
 && test "$(git rev-parse HEAD)" = "${PRISMML_COMMIT}" \
 && echo "PrismML llama.cpp pinned at ${PRISMML_COMMIT} (branch ${PRISMML_BRANCH})"

# Build apenas do `llama-server`, Release, com CUDA para a arquitetura alvo.
# BUILD_SHARED_LIBS=OFF embute o ggml no binário (autossuficiente, sem RUNPATH
# dependente do diretório de build). Não requer GPU no build (arquitetura fixa).
RUN cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" \
      -DBUILD_SHARED_LIBS=OFF \
      -DLLAMA_CURL=ON \
 && cmake --build build --config Release --target llama-server -j"$(nproc)" \
 && cp build/bin/llama-server /usr/local/bin/llama-server \
 && chmod +x /usr/local/bin/llama-server

# Sem ENTRYPOINT/CMD: `docker run <imagem> llama-server ...` resolve direto
# (comportamento exigido pelo llama-swap / testes).
WORKDIR /
