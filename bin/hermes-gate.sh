#!/usr/bin/env bash
# hermes-gate — porteiro do Hermes Agent (container "hermes").
#
# EXCEÇÃO CONTROLADA ao design não-autônomo do oraculo (README,
# "Decisões de Projeto"): o Hermes é um agente autônomo, mas só roda
# quando o humano NÃO está usando o PC — a mesma 3060 que serve os LLMs
# é a placa do desktop/jogos.
#
# Política (decidida com o usuário, 2026-10-20):
#   ACORDA  — tela bloqueada (hyprlock rodando) por LOCK_STABLE_N checagens
#             consecutivas E nenhum jogo ocupando a GPU;
#   DORME   — tela destravada (stop imediato) OU jogo na GPU (mesmo
#             travado: jogo pode ficar rodando com a sessão travada).
#
# Segurança de VRAM (espelha o gpu-shim do ComfyUI):
#   - Só acorda se hyprlock está ativo — input ativo (jogo incluído)
#     impede o lock;
#   - Mesmo travado, um processo GPU fora da allowlist do oráculo usando
#     >= GAME_MIB MiB é tratado como jogo → gate fechado;
#   - Se o gate fecha POR JOGO, pede GET :8081/unload ao llama-swap
#     (síncrono, ~0,5 s) — o mesmo endpoint que o gpu-shim usa.
#
# O container tem restart: "no" de propósito: nada revive o Hermes sem
# passar daqui. `./manage.sh stop` também o para explicitamente.
#
# Execução: systemd --user (bin/hermes-gate.service). jocic está no
# grupo docker, então o socket é acessível sem root.

set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_DIR/logs"
LOG="$LOG_DIR/hermes-gate.log"

INTERVAL_S=20          # período do loop
LOCK_STABLE_N=3        # checagens travadas consecutivas p/ acordar (3x20s)
GAME_MIB=1536          # VRAM de processo desconhecido >= isso = jogo
UNLOAD_URL="http://127.0.0.1:8081/unload"
# processos GPU legítimos do oraculo, por basename (llama-server =
# containers ls-*, python3 = ComfyUI; o resto do display não aparece
# em compute apps)
ALLOWED_GPU_RE='^(llama-server|python3?|comfyui|Hyprland|hyprland|Xorg|Xwayland)$'

mkdir -p "$LOG_DIR"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

locked() { pidof hyprlock >/dev/null 2>&1; }

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' hermes 2>/dev/null)" = "true" ]
}

# Maior uso de VRAM (MiB) entre processos GPU fora da allowlist; 0 se nada.
# process_name vem às vezes como caminho completo (/usr/local/bin/llama-server)
# — comparar pelo basename.
gpu_game_mib() {
  nvidia-smi --query-compute-apps=pid,process_name,used_memory \
    --format=csv,noheader,nounits 2>/dev/null \
    | awk -F' *, *' -v re="$ALLOWED_GPU_RE" '
        { name = $2; sub(/.*\//, "", name)
          if (name !~ re && $3+0 > max) max = $3+0 }
        END { print max+0 }'
}

ensure_stopped() {
  local reason="$1"
  container_running || return 0
  log "FECHANDO gate ($reason): parando hermes"
  (cd "$REPO_DIR" && docker compose --profile hermes stop hermes >/dev/null 2>&1) \
    || log "ERRO: docker compose stop hermes falhou"
  # Jogo apareceu com o Hermes rodando → o LLM pode estar residente na
  # VRAM (o Hermes usa llama-swap). Descarrega para o jogo respirar;
  # o próximo request recarrega sozinho.
  if [ "$reason" = "jogo na GPU com tela travada" ]; then
    curl -s --max-time 60 "$UNLOAD_URL" >/dev/null 2>&1 \
      && log "unload do llama-swap pedido" \
      || log "unload do llama-swap indisponível (proxy parado?)"
  fi
}

stable_lock=0
log "hermes-gate iniciado (intervalo ${INTERVAL_S}s; wake exige tela \
travada por ${LOCK_STABLE_N} checagens e GPU livre de jogos)"

while true; do
  if locked; then
    # teto para o contador não crescer indefinidamente
    [ "$stable_lock" -lt 1000 ] && stable_lock=$((stable_lock + 1))
  else
    if [ "$stable_lock" -ge "$LOCK_STABLE_N" ]; then
      log "tela destravada após gate aberto"
    fi
    stable_lock=0
    ensure_stopped "tela destravada"
  fi

  if [ "$stable_lock" -ge "$LOCK_STABLE_N" ]; then
    game_mib="$(gpu_game_mib)"
    if [ "$game_mib" -ge "$GAME_MIB" ]; then
      ensure_stopped "jogo na GPU com tela travada (${game_mib} MiB)"
    elif ! container_running; then
      log "ABRINDO gate: tela travada há $((stable_lock * INTERVAL_S))s; \
acordando hermes"
      if (cd "$REPO_DIR" && docker compose --profile hermes up -d hermes \
          >/dev/null 2>&1); then
        log "hermes acordado"
      else
        log "ERRO: docker compose up hermes falhou (ver data/hermes/ e compose)"
      fi
    fi
  fi

  sleep "$INTERVAL_S"
done
