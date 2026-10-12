#!/bin/bash
# Sourced pelo entrypoint da imagem (runner-scripts/entrypoint.sh) antes do
# ComfyUI iniciar. Sobe o gpu-shim na porta canônica 8188; o ComfyUI fica
# em 127.0.0.1:8189 (ver CLI_ARGS no docker-compose.yml).
nohup python3 /root/user-scripts/gpu-shim.py >> /root/ComfyUI/user/gpu-shim.log 2>&1 &
echo "[pre-start] gpu-shim iniciado (pid $!)"
