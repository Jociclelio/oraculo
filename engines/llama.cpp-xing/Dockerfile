# Engine dedicada do fork shuxiaoqiong do llama.cpp — necessária para os GGUFs
# Xing4.0 (arquitetura `xing4_0`: MoE 29B/4B + MLA + mHC hyper-connections + MTP).
#
# REGRA DURA: NUNCA usar a imagem stock (ghcr.io/ggml-org/llama.cpp) para
# Xing4.0 — o suporte à arquitetura `xing4_0` vive no PR upstream #29012
# (AIN Aberto/não mergeado); a imagem stock recusa o GGUF com erro de
# arquitetura desconhecida.
#
# Fonte: https://github.com/shuxiaoqiong/llama.cpp (branch `xing4_0-port`),
# commit PINADO — que é simultaneamente o HEAD do PR #29012 (verificado em
# 2026-10-10) e o tip da branch.
FROM nvidia/cuda:13.4.2-devel-ubuntu24.04

ARG XING_REPO="https://github.com/shuxiaoqiong/llama.cpp"
ARG XING_BRANCH="xing4_0-port"
# Commit PINADO (HEAD do PR ggml-org#29012 / tip de `xing4_0-port` em 2026-10-10).
ARG XING_COMMIT="8c379195a369cc3c6627d0eeb3e5060e2d160cd1"
# Alvo: RTX 3060 (Ampere) — mesma arquitetura do build PrismML de referência.
ARG CUDA_ARCH="86"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git cmake build-essential libcurl4-openssl-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Clone shallow da branch `xing4_0-port` com checkout forçado no commit pinado
# e verificação dura (o build falha se HEAD != commit pinado).
RUN git clone --depth 1 --branch "${XING_BRANCH}" "${XING_REPO}" . \
 && git fetch --depth 1 origin "${XING_COMMIT}" \
 && git checkout --detach "${XING_COMMIT}" \
 && test "$(git rev-parse HEAD)" = "${XING_COMMIT}" \
 && echo "shuxiaoqiong llama.cpp pinned at ${XING_COMMIT} (branch ${XING_BRANCH})"

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
