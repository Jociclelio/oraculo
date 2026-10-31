#!/bin/bash
# Sourced pelo entrypoint da imagem (runner-scripts/entrypoint.sh) antes do
# ComfyUI iniciar. Sobe o gpu-shim na porta canônica 8188; o ComfyUI fica
# em 127.0.0.1:8189 (ver CLI_ARGS no docker-compose.yml).
# A imagem slim NÃO traz aiohttp (a cu126 antiga trazia) — auto-heal aqui:
# PIP_USER + HOME=/root (HOME default do uid 1000 é "/", root-owned, e pip
# user-install morreu em silêncio) → instala em /root/.local, que persiste
# no volume comfyui-root. Sem isso o gpu-shim morre no import.
# ATENÇÃO: o ComfyUI da imagem cu130 roda em python3.13 (/usr/local);
# o `python3` do PATH é um 3.12 base sem torch — NÃO usar para o shim.
export HOME=/root          # python user-site (/root/.local) sobrevive ao restart
export PIP_USER=true
export PIP_ROOT_USER_ACTION=ignore
python3.13 -c "import aiohttp" 2>/dev/null || pip install --quiet aiohttp
nohup python3.13 /root/user-scripts/gpu-shim.py >> /root/ComfyUI/user/gpu-shim.log 2>&1 &
echo "[pre-start] gpu-shim iniciado (pid $!)"

# input/ vive em /tmp (volátil) — recriar o placeholder.png OBRIGATÓRIO dos 9
# slots vazios do workflow de edição (sem ele a validação do ComfyUI rejeita
# o prompt com "Invalid image file: placeholder.png", HTTP 400).
if [ ! -f /root/ComfyUI/input/placeholder.png ]; then
  python3 -c "from PIL import Image; Image.new('RGB',(64,64),(128,128,128)).save('/root/ComfyUI/input/placeholder.png')" \
    && echo "[pre-start] placeholder.png recriado"
fi
