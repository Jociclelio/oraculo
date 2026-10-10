#!/bin/bash
# install.sh — baixa o binário de release mais recente do llama-swap
# https://github.com/mostlygeek/llama-swap
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# instala em bin/ na raiz do repositório (caminho esperado pelo manage.sh)
BIN_DIR="$SCRIPT_DIR/../bin"
REPO="mostlygeek/llama-swap"

# --- Arquitetura ---
case "$(uname -m)" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "Erro: arquitetura não suportada: $(uname -m)" >&2
    echo "Este script suporta apenas x86_64 (amd64) e aarch64 (arm64)." >&2
    exit 1
    ;;
esac

# --- Última release via API do GitHub ---
echo "Consultando última release de $REPO..."
TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -oP '"tag_name":\s*"\K[^"]+' || true)"
if [ -z "$TAG" ]; then
  echo "Erro: não foi possível obter a última release (falha na API do GitHub)." >&2
  exit 1
fi
VERSION="${TAG#v}"  # assets não usam o prefixo "v" (ex.: llama-swap_263_linux_amd64.tar.gz)
ASSET="llama-swap_${VERSION}_linux_${ARCH}.tar.gz"
URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"

echo "Baixando $URL ..."
mkdir -p "$BIN_DIR"
TMPDIR_DL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_DL"' EXIT

if ! curl -fSL --retry 3 -o "$TMPDIR_DL/$ASSET" "$URL"; then
  echo "Erro: falha no download do asset $ASSET." >&2
  echo "Verifique se a release $TAG existe e se a rede está acessível." >&2
  exit 1
fi

tar -xzf "$TMPDIR_DL/$ASSET" -C "$TMPDIR_DL"
if [ ! -f "$TMPDIR_DL/llama-swap" ]; then
  echo "Erro: binário 'llama-swap' não encontrado dentro do arquivo $ASSET." >&2
  exit 1
fi

mv "$TMPDIR_DL/llama-swap" "$BIN_DIR/llama-swap"
chmod +x "$BIN_DIR/llama-swap"

echo "Instalado: $BIN_DIR/llama-swap ($TAG, linux/$ARCH)"
"$BIN_DIR/llama-swap" --version 2>/dev/null || true
