# syntax=docker/dockerfile:1
#
# Strata (Qwen3.8-Flash-Next) — imagem do engine para o repo oraculo.
#
# Adaptado do Dockerfile oficial do upstream (https://github.com/Niko1221/Strata,
# commit pinado abaixo). Diferenças em relação ao upstream:
#   - O código do Strata NÃO é vendored neste repo: o build clona o upstream no
#     commit STRATA_REF com verificação dura (mesmo padrão da engine PrismML da
#     task 003) — o build é reprodutível e `docker build strata/` funciona
#     standalone a partir do repo.
#   - CUDA_ARCHITECTURES estreitado para 86 (RTX 3060, Ampere): o upstream compila
#     um binário "gordo" com cubin para 75;80;86;89;120; aqui basta sm_86 e o
#     build é bem mais rápido. Card de outra arquitetura exigiria rebuild com a
#     própria arch (CMakeLists do upstream recusa arch < 75).
#   - Defaults das env MODEL/FAMILY/CONTEXT fixados para a variante Coder com o
#     contexto alvo do plano (é a única variante que cabe nos 31 GB de RAM desta
#     máquina — ver strata/README.md). As três env são lidas pelo
#     docker-entrypoint.sh do upstream no primeiro start e continuam
#     sobrescrevíveis com `docker run -e ...`.
#   - Os pesos do modelo (~70 GB) NÃO são baixados no build: o download acontece
#     no PRIMEIRO start do container (setup.py --setup), gravando no volume
#     /data — montar em /home (NVMe), ver strata/README.md.
#
# Build (compila a engine; não requer GPU, não baixa pesos):
#   docker build -t strata ./strata
#
# Run (host precisa de driver NVIDIA >= 580 e nvidia-container-toolkit):
#   docker run --rm --gpus all \
#     -p 127.0.0.1:8080:8080 \
#     --ulimit memlock=-1 \
#     -v /home/jocic/strata-data:/data \
#     strata
#
# API OpenAI/Anthropic-compatible em http://127.0.0.1:8080/v1 após o modelo
# carregar (1-3 min em starts seguintes; o primeiro baixa ~70 GB).

FROM nvidia/cuda:13.0.0-devel-ubuntu24.04

# Commit PINADO do upstream (tip de `main` em 2026-10-10, conferido via API
# do GitHub no dia). Nunca usar main solto: o build precisa ser reprodutível.
ARG STRATA_REF=61b3fb5dd3f1e8ec09cf7e4e05208bc6d3c46406

# Semântica das env PRESERVADA do upstream — lidas pelo docker-entrypoint.sh:
#   FAMILY  — família/modelo no HF ("qwen" = tag vazia; "coder" = variante Coder,
#             metade dos experts, cabe em 32 GB de RAM)
#   MODEL   — variante/quant a instalar no primeiro start
#   CONTEXT — contexto alvo em tokens
# Outras env do entrypoint (VISION, KV, GPU/GPUS, LOW_RAM, API_KEY, GGUF_DIR,
# RESIDENT_BUDGET_GIB, KV_STREAMING, CONFIG) seguem com os defaults upstream.
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    STRATA_EXECV=1 \
    FAMILY=coder \
    MODEL=coder \
    CONTEXT=65536

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git libatomic1 libgomp1 \
        python3 python3-pip python3-venv unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/strata

# Clone do upstream com checkout forçado no commit pinado e verificação dura
# (o build falha se HEAD != STRATA_REF).
RUN git clone https://github.com/Niko1221/Strata.git . \
    && git fetch --depth 1 origin "${STRATA_REF}" \
    && git checkout --detach "${STRATA_REF}" \
    && test "$(git rev-parse HEAD)" = "${STRATA_REF}" \
    && chmod +x setup.sh docker-entrypoint.sh \
    && echo "Strata pinned at ${STRATA_REF}"

# RTX 3060 = sm_86 (ver cabeçalho). BUILD_VISION=0 pularia o encoder de imagem;
# mantido (Strata suporta input de imagem).
ARG CUDA_ARCHITECTURES=86
ARG BUILD_VISION=1

RUN python3 -m venv .venv \
    && .venv/bin/pip install --no-cache-dir --upgrade pip \
    && .venv/bin/pip install --no-cache-dir -r requirements.txt

# llama.cpp no commit pinado pelo setup.py, e a engine + encoder de visão,
# compilados exatamente como o setup.py compila: código nativo para a CPU que
# faz o build (buildar nesta máquina). O BUILD.json é o que o setup.py lê para
# decidir se a engine está atual: source=local com hash de src compatível faz o
# primeiro start reaproveitar em vez de recompilar.
#
# NOTA DE ADAPTAÇÃO: o upstream embute este script como heredoc no RUN; aqui ele
# é um arquivo próprio (build-engine.py) porque o builder Docker desta máquina
# (sem buildx) não suporta heredoc — com heredoc, o RUN "passava" sem executar
# nada (python lê stdin vazio e sai 0) e a imagem saía SEM a engine.
COPY build-engine.py .

RUN .venv/bin/python build-engine.py

# as árvores cmake são só de build; a engine compilada é o que o container usa
RUN rm -rf build build-vision

VOLUME ["/data"]
EXPOSE 8080

# /health responde antes do gate de API key. A porta só abre depois do modelo
# carregar (1-3 min; mais no primeiro run), por isso o start-period generoso:
# um período curto marcaria como unhealthy um container ainda carregando e um
# restart policy o mataria no meio do download.
HEALTHCHECK --interval=30s --timeout=5s --start-period=600s --retries=3 \
  CMD curl -fs "http://127.0.0.1:${PORT:-8080}/health" || exit 1

ENTRYPOINT ["./docker-entrypoint.sh"]
