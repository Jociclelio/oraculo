# mcp-comfyui — ComfyUI MCP Server (joenorton) para o Open WebUI
#
# Clone do upstream pinado em commit + patch oraculo (ver patches/oraculo.patch):
#   1. managers/workflow_manager.py — params image_ref_2..image_ref_10 viram
#      OPCIONAIS (referências do workflow de edição; default placeholder.png
#      vem do config.json de defaults). Sem isso as 9 refs viriam required
#      no schema da tool e o modelo teria que passá-las sempre.
#   2. server.py — host/port do MCP via env MCP_HOST/MCP_PORT (default
#      127.0.0.1:8933; upstream hardcode 9000).
#   3. comfyui_client.py — max_attempts 30→300 (poll de 1 s). O default de
#      30 s estoura com wake frio: pesos voltando da RAM + unload do LLM
#      pelo gpu-shim (teto de 45 s no shim sozinho). Jobs que passam de
#      300 s ainda retornam prompt_id p/ polling com get_job.
#   4. managers/workflow_manager.py — (a) descrição da tool vem do
#      <workflow>.meta.json; (b) _load_workflows ignora *.meta.json.
#   5. asset_processor.py + tools/asset.py — previews inline em JPEG, NÃO
#      WebP: o llama.cpp (mtmd/stb_image) não decodifica WebP, então a
#      imagem devolvida por view_image/inline preview voltava no request
#      seguinte e o modelo falhava com 400 "Failed to load image or audio
#      file" (ou segfaultava, exit 139, no fork bonsai-ada) — era a causa
#      do "Stream ended without finish_reason" no pi.
FROM python:3.12-slim

# git só para o clone pinado (o build FALHA se o commit não existir)
RUN apt-get update \
 && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/*

ARG PIN=e0101b2312f30501664dabe4a74c1283c4268eb8
RUN git clone --quiet https://github.com/joenorton/comfyui-mcp-server /app \
 && git -C /app checkout --quiet ${PIN}

COPY patches/oraculo.patch /tmp/oraculo.patch
RUN cd /app \
 && git apply --check /tmp/oraculo.patch \
 && git apply /tmp/oraculo.patch \
 && rm /tmp/oraculo.patch

# requirements.txt do upstream puxa pytest (dev) — instalamos só o runtime.
# mcp pinado <2: o 2.x renomeou FastMCP → MCPServer (API incompatível)
RUN pip install --no-cache-dir "requests>=2.31.0" "mcp>=0.9.0,<2" "Pillow>=10.0.0"

ENV COMFYUI_URL=http://127.0.0.1:8188 \
    COMFY_MCP_WORKFLOW_DIR=/workflows \
    MCP_HOST=127.0.0.1 \
    MCP_PORT=8933

WORKDIR /app
CMD ["python", "server.py"]
