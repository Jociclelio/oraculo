# Engine dedicada do llama.cpp STOCK (ggml-org) + patch de prompt disk cache
# (fork qqkzlm/llama-cpp-prompt-disk-cache, porta manual para o master).
#
# Motivação (regra 9 do AGENTS.md): o unload do llama-swap (gpu-shim antes do
# ComfyUI, swap entre modelos ou ttl: 300) destrói o KV cache junto com o
# container — toda conversa volta a pagar prefill inteiro. O /slots save/
# restore do stock NÃO serializa context checkpoints em modelos híbridos/SWA
# (bug ggml-org/llama.cpp#28194, aberto em 2026-10-17). Este patch (v0.1.0 do
# qqkzlm) resolve por outro caminho: snapshots COMPLETOS `.centry` (tokens +
# todo o estado de sequência) escritos atomicamente em disco no fim do slot e
# restaurados via L2 do prompt cache no PRÓXIMO request após o (re)start —
# sem orquestração no gpu-shim e sem depender do /slots.
#
# POR QUE NÃO a imagem do próprio fork (branch main dele)? MEDIDO em
# 2026-10-17: a linhagem `prism` (PrismML) tem o caminho de MoE com experts
# na CPU NÃO otimizado — prefill de 21k tokens a 35→18 tok/s (vs 800 tok/s do
# stock) com -ncmoe 31 + --load-mode none, com e sem o cache de disco ligado.
# O mesmo collapse ocorre na NOSSA engine prismml 84445367f. Como quase todo
# o zoológico é MoE híbrido servido com experts na CPU (regra 2), o patch foi
# portado para o master do ggml-org. Conflitos resolvidos à mão em
# common/arg.cpp (bloco de opções), tools/server/CMakeLists.txt (vendor::hash)
# e tools/server/server-context.cpp (update_slot com is_stateless() do master;
# prompt_disk_save; hunks de prefix-only descartados — modo desabilitado).
#
# Fonte: https://github.com/ggml-org/llama.cpp, commit PINADO = o MESMO commit
# da imagem stock ghcr.io/ggml-org/llama.cpp:full-cuda em uso (build 12063).
# LIMITAÇÃO: nenhuma esperada — mesma base do stock, mesmos modelos servidos.
FROM nvidia/cuda:13.4.2-devel-ubuntu24.04

ARG STOCK_REPO="https://github.com/ggml-org/llama.cpp"
# Commit PINADO — igual ao da imagem stock em uso:
#   version: 1.0.0-dev (build 12464, commit d3c3e242c; imagem atualizada
#   2026-11-17, antes build 12063 / 2cbca389f)
ARG STOCK_COMMIT="d3c3e242c16b8cbf51400fad410cd69b22d64f35"
# Alvo: RTX 3060 (Ampere) — mesma arquitetura do build nativo de referência.
ARG CUDA_ARCH="86"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git cmake build-essential libcurl4-openssl-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Clone shallow do master com checkout forçado no commit pinado e verificação
# dura (o build falha se HEAD != commit pinado).
RUN git clone --depth 1 "${STOCK_REPO}" . \
 && git fetch --depth 1 origin "${STOCK_COMMIT}" \
 && git checkout --detach "${STOCK_COMMIT}" \
 && test "$(git rev-parse HEAD)" = "${STOCK_COMMIT}" \
 && echo "stock llama.cpp pinned at ${STOCK_COMMIT}"

# Aplica o patch portado do prompt disk cache (falha o build se não aplicar).
COPY 0001-pdcache-stock-port.patch /tmp/
RUN git apply --check /tmp/0001-pdcache-stock-port.patch \
 && git apply /tmp/0001-pdcache-stock-port.patch \
 && echo "patch prompt-disk-cache aplicado"

# Build apenas do `llama-server`, Release, com CUDA para a arquitetura alvo.
# BUILD_SHARED_LIBS=OFF embute o ggml no binário (autossuficiente, sem RUNPATH
# dependente do diretório de build). Não requer GPU no build (arquitetura fixa).
# LLAMA_UI_HF_BUCKET inválido: a UI "latest" do bucket ggml-org não passa na
# validação do ui-assets.cmake (asset workbox[hash].js removido do bucket
# depois do build 12464) e o build morre em FATAL_ERROR. Com bucket inválido o
# download falha e o script segue o fallback OFICIAL ("building without an
# embedded UI") — irrelevante para serving por API (llama-swap), sem UI web.
RUN cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" \
      -DBUILD_SHARED_LIBS=OFF \
      -DLLAMA_CURL=ON \
      -DLLAMA_UI_HF_BUCKET=invalid/sem-ui \
 && cmake --build build --config Release --target llama-server -j"$(nproc)" \
 && cp build/bin/llama-server /usr/local/bin/llama-server \
 && chmod +x /usr/local/bin/llama-server

# Sem ENTRYPOINT/CMD: `docker run <imagem> llama-server ...` resolve direto
# (mesmo comportamento da engine prismml; o macro docker-pdcache usa
# --entrypoint porque a base nvidia/cuda herda nvidia_entrypoint.sh).
WORKDIR /
