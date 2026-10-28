# Engine "bonsai-ada" — fork llama.cpp-ada-ternary (branch `bonsai-q8-product`)
# do projeto bonsai-ada-surgery (professorpalmer), a pilha de 71 patches sobre
# o PrismML `adfffbe` (equivalente verificada ao `git am` da série patches/).
#
# Por que existe (além da engine llama.cpp-prismml pinada 84445367f):
#   - KV cache TIERED (--kv-vram-cells): posições [0,N) em VRAM, o resto em
#     RAM pinneada mapeada no mesmo espaço CUDA — output bit-idêntico, decode
#     degrada graciosamente via PCIe em vez de limitar o ctx.
#   - MTP self-draft com a head ProCreations enxertada no GGUF (draft-mtp,
#     sem --model-draft) + lookup drafting (n-gram) na frente.
#   - FA lê q4_0/q8_0/q3_0 K/V in place (patch 0009) — no fork PrismML stock
#     o q5_1 não tem caminho rápido (issue PrismML #191); aqui o q4_0 é o
#     caminho rápido natural.
#   - Harness-proofing (--reasoning-effort-allow/-fallback,
#     --reasoning-max-tokens-floor, packed KQ mask, shared CUDA pool).
# Pesos NÃO mudam: os 851 tensors do trunk são byte-idênticos ao PTQ1_0 do
# PrismML (GGUF pronto: CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF no HF).
#
# Fonte: https://github.com/professorpalmer/llama.cpp-ada-ternary
#        (branch `bonsai-q8-product`), commit PINADO (nunca HEAD).
# Base declarada do patch stack: PrismML-Eng/llama.cpp `adfffbe` + patches/
# 0001-0071 do repo bonsai-ada-surgery (ver docs/build/PATCHES.md lá).
FROM nvidia/cuda:13.4.2-devel-ubuntu24.04

ARG ADA_REPO="https://github.com/professorpalmer/llama.cpp-ada-ternary"
ARG ADA_BRANCH="bonsai-q8-product"
# Commit PINADO (tip de `bonsai-q8-product` em 2026-10-26; "tests: flash
# attention cases for the chunked prefill path, packed (I32) mask option").
ARG ADA_COMMIT="2cadbfb64026b77293a76cf1a2d16e1aefeee45d"
# Alvo: RTX 3060 (Ampere, sm_86) — mesma arquitetura do build nativo.
ARG CUDA_ARCH="86"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git cmake build-essential libcurl4-openssl-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Clone shallow da branch `bonsai-q8-product` com checkout forçado no commit
# pinado e verificação dura (o build falha se HEAD != commit pinado).
RUN git clone --depth 1 --branch "${ADA_BRANCH}" "${ADA_REPO}" . \
 && git fetch --depth 1 origin "${ADA_COMMIT}" \
 && git checkout --detach "${ADA_COMMIT}" \
 && test "$(git rev-parse HEAD)" = "${ADA_COMMIT}" \
 && echo "llama.cpp-ada-ternary pinned at ${ADA_COMMIT} (branch ${ADA_BRANCH})"

# Build apenas do `llama-server`, Release, CUDA para a arquitetura alvo.
# BUILD_SHARED_LIBS=OFF embute o ggml no binário (mesmo padrão da engine
# prismml). Não requer GPU no build (arquitetura fixa).
RUN cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" \
      -DBUILD_SHARED_LIBS=OFF \
      -DLLAMA_CURL=ON \
 && cmake --build build --config Release --target llama-server -j"$(nproc)" \
 && cp build/bin/llama-server /usr/local/bin/llama-server \
 && chmod +x /usr/local/bin/llama-server

# Sem ENTRYPOINT/CMD explícito: a base nvidia/cuda herda nvidia_entrypoint.sh
# (mesmo comportamento da engine prismml — o macro docker-bonsai-ada sobrescreve
# com --entrypoint /usr/local/bin/llama-server).
WORKDIR /
