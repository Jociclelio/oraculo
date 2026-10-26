#!/bin/bash
# Sourced pelo entrypoint da imagem (runner-scripts/entrypoint.sh) antes do
# ComfyUI iniciar. Sobe o gpu-shim na porta canônica 8188; o ComfyUI fica
# em 127.0.0.1:8189 (ver CLI_ARGS no docker-compose.yml).
nohup python3 /root/user-scripts/gpu-shim.py >> /root/ComfyUI/user/gpu-shim.log 2>&1 &
echo "[pre-start] gpu-shim iniciado (pid $!)"

# input/ vive em /tmp (volátil) — recriar o placeholder.png OBRIGATÓRIO dos 9
# slots vazios do workflow de edição (sem ele a validação do ComfyUI rejeita
# o prompt com "Invalid image file: placeholder.png", HTTP 400).
if [ ! -f /root/ComfyUI/input/placeholder.png ]; then
  python3 -c "from PIL import Image; Image.new('RGB',(64,64),(128,128,128)).save('/root/ComfyUI/input/placeholder.png')" \
    && echo "[pre-start] placeholder.png recriado"
fi
