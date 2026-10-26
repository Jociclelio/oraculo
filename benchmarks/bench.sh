#!/bin/bash
# ============================================================================
# benchmarks/bench.sh v2 — curvas de desempenho do zoológico
#
# Uso:
#   ./bench.sh <entry|all> [série...]   # séries: sweep pp3d (default: ambas)
#   BENCH_REPS=2 ./bench.sh all         # reps do pp3d (default 2)
#   DRY=1 ./bench.sh all                # só imprime comandos
#
# Séries:
#   sweep — llama-server e2e (receita de serving: mmproj/visão plena, KV
#           q5_1/iq4_nl, ncmoe de serving ≈ corte 10 GB): requests de
#           contexto crescente (≈0,16k,32k,64k,96k,127k tokens) medindo
#           prefill tok/s e decode tok/s COM O CONTEXTO CHEIO.
#           Alimenta: decode×ctx, prefill×ctx, tempo×ctx.
#   pp3d  — llama-bench: superfície batch × ubatch → prefill tok/s
#           (p=8192, n=0). Alimenta: gráfico 3D de prefill.
#
# Resultados: results/<entry>__e2e.csv e results/<entry>__pp3d.csv
# ============================================================================
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)
RESULTS=benchmarks/results
mkdir -p "$RESULTS"
PORT=${BENCH_PORT:-18080}
REPS=${BENCH_REPS:-2}
DRY=${DRY:-0}
STOCK_IMG=${STOCK_IMG:-ghcr.io/ggml-org/llama.cpp:full-cuda}

declare -A GGUF IMG MOE NCMOE MMPROJ UB B
GGUF[Gemma4_12B]="gemma-4-12B-it-qat-UD-Q4_K_XL/gemma-4-12B-it-qat-UD-Q4_K_XL.gguf"
GGUF[Qwen3.6_35B_A3B]="unsloth_Qwen3.6_35B_A3B_MTP/Qwen3.6-35B-A3B-MTP-Q4_K_M.gguf"
GGUF[Qwen3.6_35B_A3B_Hauhau_Aggressive]="Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
GGUF[Ornith1.5_35B_MTP]="Ornith-1.5-35B-MTP-APEX-Compact/Ornith-1.5-35B-A3B-APEX-MTP-Compact.gguf"
GGUF[LFM2.5_24B_A2B]="LFM2.5-24B-A2B-GGUF/LFM2.5-24B-A2B-Q4_K_M.gguf"
GGUF[Qwen3.8_35B_Distill]="Qwen3.8-35B-A3B-Distill-Q4_K_M/Qwen3.8-35B-A3B-Q4_K_M.gguf"
GGUF[MiniCPM-V_4.7_35B]="MiniCPM-V-4.7-35B-A3B-Q4_K_M/MiniCPM-V-4_7-35B-A3B-Q4_K_M.gguf"
GGUF[Flint_40B_A2.5B]="Flint-GGUF/Flint-Q4_K_M.gguf"
GGUF[bonsai-27b]="Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PTQ1_0.gguf"
GGUF[Xing4.0_29B_A4B]="Xing4.0-29B-A4B-Q4_K_M/Xing4.0-29B-A4B-Q4_K_M.gguf"

for m in "${!GGUF[@]}"; do IMG[$m]=stock; MOE[$m]=0; NCMOE[$m]=0; MMPROJ[$m]=""; UB[$m]=2048; B[$m]=4096; done
MOE[Qwen3.6_35B_General]=1; NCMOE[Qwen3.6_35B_General]=33
MOE[Qwen3.6_35B_Code]=1;    NCMOE[Qwen3.6_35B_Code]=31
MOE[Qwen3.6_35B_A3B_Hauhau_Aggressive]=1; NCMOE[Qwen3.6_35B_A3B_Hauhau_Aggressive]=29
MOE[Ornith1.5_35B_MTP]=1;   NCMOE[Ornith1.5_35B_MTP]=29
MOE[LFM2.5_24B_A2B]=1;      NCMOE[LFM2.5_24B_A2B]=20
MOE[Qwen3.8_35B_Distill]=1; NCMOE[Qwen3.8_35B_Distill]=31
MOE[MiniCPM-V_4.7_35B]=1;   NCMOE[MiniCPM-V_4.7_35B]=32
MOE[Flint_40B_A2.5B]=1;     NCMOE[Flint_40B_A2.5B]=38
MOE[Xing4.0_29B_A4B]=1;     NCMOE[Xing4.0_29B_A4B]=27
IMG[bonsai-27b]=prismml
IMG[Xing4.0_29B_A4B]=xing
UB[Xing4.0_29B_A4B]=1024
# bonsai: serving não define -b/-ub (defaults do llama-server: b2048/ub512) —
# forçar ub2048 estoura o compute buffer com ~1,5 GB de folga → thrashing
UB[bonsai-27b]=""
B[bonsai-27b]=""

MMPROJ[Gemma4_12B]="gemma-4-12B-it-qat-UD-Q4_K_XL/mmproj-F32.gguf"
MMPROJ[Qwen3.6_35B_General]="unsloth_Qwen3.6_35B_A3B_MTP/mmproj-F16.gguf"
MMPROJ[Qwen3.6_35B_Code]="unsloth_Qwen3.6_35B_A3B_MTP/mmproj-F16.gguf"
MMPROJ[Qwen3.6_35B_A3B_Hauhau_Aggressive]="Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf"
MMPROJ[Ornith1.5_35B_MTP]="Ornith-1.5-35B-MTP-APEX-Compact/mmproj.gguf"
MMPROJ[Qwen3.8_35B_Distill]="Qwen3.8-35B-A3B-Distill-Q4_K_M/mmproj-Qwen3.8-35B-A3B-F16.gguf"
MMPROJ[MiniCPM-V_4.7_35B]="MiniCPM-V-4.7-35B-A3B-Q4_K_M/mmproj-model-f16.gguf"
MMPROJ[bonsai-27b]="Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf"

# KV de serving: tipo ÚNICO q5_1/q5_1 (regra 10 — K/V misto quebra GDN)
declare -A KV
for m in "${!GGUF[@]}"; do KV[$m]="q5_1:q5_1"; done

img_ref() { case $1 in stock) echo "$STOCK_IMG";; prismml) echo "llama.cpp-prismml:latest";; xing) echo "llama.cpp-xing:latest";; esac; }
entptr()  { case $1 in stock) echo "/app/llama-server";; *) echo "/usr/local/bin/llama-server";; esac; }
benchptr(){ case $1 in stock) echo "/app/llama-bench";; *) echo "/usr/local/bin/llama-bench";; esac; }

# ---------------------------------------------------------------------------
# Série sweep — llama-server e2e: contexto crescente, prefill + decode
# ---------------------------------------------------------------------------
CTX_POINTS=(16 16384 32768 65536 98304 126976)

prompt_tokens() { # $1=alvo de tokens → imprime prompt (palavras variadas,
  # sem prefixo comum entre pontos para não acionar cache-reuse)
  python3 - "$1" <<'EOF'
import sys, random
target = int(sys.argv[1])
if target < 32:
    print("Responda apenas: ok")
    sys.exit()
random.seed(target)  # seed por tamanho: prompts de tamanhos distintos não
words = ("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo "
         "lima mike november oscar papa quebec romeo sierra tango uniform "
         "victor whiskey xray yankee zulu linha casa poço torre nuvem ponte "
         "laranja teclado janela mercado cavalo estrela caminho violão").split()
out = []
n = 0
while n < target:
    w = random.choice(words)
    out.append(w); n += len(w) // 3 + 1  # ~1.33 tokens/palavra (aprox.)
print(" ".join(out))
EOF
}

sweep() { # $1=entry
  local entry=$1
  local out="$RESULTS/${entry}__e2e.csv"
  local cname="bench-e2e-${entry//./-}"
  local -a cmd=(docker run --rm --name "$cname" --gpus all
    --entrypoint "$(entptr "${IMG[$entry]}")"
    -p "127.0.0.1:${PORT}:8080" -v "$ROOT/models:/models"
    "$(img_ref "${IMG[$entry]}")"
    --host 0.0.0.0 --port 8080 -fa on --jinja -np 1 -t 5
    -ctk "${KV[$entry]%%:*}" -ctv "${KV[$entry]##*:}"
    --cache-reuse 256
    -m "/models/${GGUF[$entry]}")
  [ -n "${MMPROJ[$entry]}" ] && cmd+=(--mmproj "/models/${MMPROJ[$entry]}")
  if [ "${MOE[$entry]}" = 1 ]; then
    cmd+=(--load-mode none -ncmoe "${NCMOE[$entry]}")
  fi
  cmd+=(-c 131072 -ngl 99)
  [ -n "${B[$entry]}" ] && cmd+=(-b "${B[$entry]}" -ub "${UB[$entry]}")
  echo "[sweep] $entry :: server up" >&2
  if [ "$DRY" = 1 ]; then echo "  DRY: ${cmd[*]}" >&2; return 0; fi

  "${cmd[@]}" > "$RESULTS/${entry}__e2e.server.log" 2>&1 &
  local spid=$!
  # espera health (até 5 min; carga fria de GGUF grande)
  # curl -f: /health responde 503 "Loading model" enquanto carrega
  local up=0
  for i in $(seq 1 100); do
    curl -sf -m 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 && { up=1; break; }
    sleep 3
  done
  if [ "$up" != 1 ]; then
    echo "$(date +%F' '%T) FALHA: server não subiu ($entry)" >> "$RESULTS/${entry}__e2e.errors.log"
    kill "$spid" 2>/dev/null; docker rm -f "$cname" >/dev/null 2>&1
    return 1
  fi
  # VRAM de pico durante o sweep (amostra a cada 2 s)
  ( local_max=0
    while kill -0 "$spid" 2>/dev/null; do
      v=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
      [ -n "$v" ] && [ "$v" -gt "$local_max" ] && local_max=$v
      sleep 2
    done
    echo "$local_max" > "$RESULTS/.vram_${entry}" ) &
  local sampler=$!
  [ -f "$out" ] || echo "entry,target_ctx,prompt_n,prefill_tps,decode_tps,prefill_s,decode_s,total_s" > "$out"
  for X in "${CTX_POINTS[@]}"; do
    local P; P=$(prompt_tokens "$X")
    # corpo via ARQUIVO: prompt grande como argumento do curl estoura o
    # MAX_ARG_STRLEN (128 KiB) do exec — pontos ≥ ~32k falhavam com -d "$body"
    local bodyfile; bodyfile=$(mktemp)
    python3 -c "
import json, sys
print(json.dumps({'prompt': sys.stdin.read(), 'n_predict': 128}))" <<< "$P" > "$bodyfile"
    local resp
    resp=$(curl -s -m 900 "http://127.0.0.1:${PORT}/completion" \
      -H "Content-Type: application/json" -d @"$bodyfile")
    rm -f "$bodyfile"
    if ! echo "$resp" | grep -q '"timings"'; then
      echo "$(date +%F' '%T) FALHA X=$X ($entry): $(echo "$resp" | head -c 200)" >> "$RESULTS/${entry}__e2e.errors.log"
    fi
    echo "$resp" | python3 -c "
import csv, json, sys
entry, target, out = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.load(sys.stdin)
    t = d['timings']
    pn = t['prompt_n']; pp = t['prompt_per_second']; tg = t['predicted_per_second']
    ps = pn/pp if pp else 0; tgs = t['predicted_n']/tg if tg else 0
    row = [entry, target, pn, f'{pp:.2f}', f'{tg:.2f}', f'{ps:.2f}', f'{tgs:.2f}', f'{ps+tgs:.2f}']
except Exception as e:
    row = [entry, target, -1, 0, 0, 0, 0, 0]
with open(out, 'a', newline='') as f:
    csv.writer(f).writerow(row)
" "$entry" "$X" "$out" || echo "$(date +%F' '%T) FALHA: request X=$X ($entry)" >> "$RESULTS/${entry}__e2e.errors.log"
  done
  kill "$sampler" 2>/dev/null
  [ -f "$RESULTS/.vram_${entry}" ] && echo "  VRAM pico: $(cat "$RESULTS/.vram_${entry}") MiB" >&2
  kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
  docker rm -f "$cname" >/dev/null 2>&1
  return 0
}

# ---------------------------------------------------------------------------
# Série pp3d — llama-bench: batch × ubatch → prefill tok/s (p=8192, n=0)
# ---------------------------------------------------------------------------
pp3d() { # $1=entry
  local entry=$1
  local out="$RESULTS/${entry}__pp3d.csv"
  local err="$RESULTS/${entry}__pp3d.errors.log"
  local -a base=(docker run --rm --gpus all
    --entrypoint "$(benchptr "${IMG[$entry]}")"
    -v "$ROOT/models:/models"
    "$(img_ref "${IMG[$entry]}")"
    -m "/models/${GGUF[$entry]}" -ngl 99 -t 5 -fa on -r "$REPS" -o csv
    -p 8192 -n 0)
  [ "${MOE[$entry]}" = 1 ] && base+=(-ncmoe "${NCMOE[$entry]}" -lm none)
  base+=(-ctk "${KV[$entry]%%:*}" -ctv "${KV[$entry]##*:}")
  echo "[pp3d] $entry" >&2
  if [ "$DRY" = 1 ]; then echo "  DRY: ${base[*]} (b×ub filtrado ub<=b)" >&2; return 0; fi
  local tmp; tmp=$(mktemp)
  : > "$tmp"
  for b in 512 1024 2048 4096; do
    local ubs=""
    for ub in 256 512 1024 2048; do [ "$ub" -le "$b" ] && ubs="${ubs:+$ubs,}$ub"; done
    [ -z "$ubs" ] && continue
    echo "[pp3d]   b=$b ub=$ubs" >&2
    if ! timeout -k 30 3300 "${base[@]}" -b "$b" -ub "$ubs" >> "$tmp" 2>> "$err"; then
      echo "$(date +%F' '%T) FALHA: b=$b ub=$ubs" >> "$err"
    fi
  done
  if [ -s "$tmp" ]; then
    if [ -f "$out" ]; then tail -n +2 "$tmp" >> "$out"; else mv "$tmp" "$out"; fi
  fi
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Main. BENCH_LIB=1 source benchmarks/bench.sh — uso como biblioteca de
# metadados/funções (calibrate.sh): define tudo e retorna sem executar.
# ---------------------------------------------------------------------------
if [ "${BENCH_LIB:-0}" = 1 ]; then
  return 0 2>/dev/null || exit 0
fi

MAIN_SERIES=(sweep pp3d)
sel=${1:-}; shift || true
[ -n "$sel" ] || { echo "uso: $0 <entry|all> [série...]"; exit 1; }
series=("$@"); [ ${#series[@]} -eq 0 ] && series=("${MAIN_SERIES[@]}")

entries=()
if [ "$sel" = all ]; then
  declare -A seen=()
  for e in "${!GGUF[@]}"; do
    k="${GGUF[$e]}|${NCMOE[$e]}"
    [ -z "${seen[$k]:-}" ] && { seen[$k]=1; entries+=("$e"); }
  done
else
  entries=("$sel")
fi

for entry in "${entries[@]}"; do
  [ -f "models/${GGUF[$entry]}" ] || { echo "[skip] $entry: GGUF ausente" >&2; continue; }
  echo "===== $entry =====" >&2
  for s in "${series[@]}"; do
    case $s in
      sweep|pp3d) "$s" "$entry";;
      *) echo "série desconhecida: $s" >&2; exit 1;;
    esac
  done
done
echo "OK — resultados em $RESULTS/" >&2
