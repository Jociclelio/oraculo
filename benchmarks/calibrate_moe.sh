#!/bin/bash
# ============================================================================
# benchmarks/calibrate_moe.sh v1 — calibração automática do cache de experts
# (--moe-cache-mib × --moe-cache-cpu-share), eleição por DECODE tok/s e2e.
#
# Irmão do calibrate.sh (que calibra b×ub por PREFILL — regra 7). O cache de
# experts NÃO muda prefill de forma relevante neste envelope (cobertura ~4-6%
# dos experts << joelho 20-30%) mas afeta o DECODE: experts quentes ficam na
# VRAM (sem subir via PCIe) e, com --moe-cache-cpu-share, parte dos misses é
# computada direto na CPU a partir dos experts na RAM em vez de transferida.
#
# Método por combo (isolado em container próprio, sem contaminação):
#   1. sobe llama-server com a RECEITA DE SERVING da entry + o par (mib,share)
#   2. warm-up curto (n_predict=8) — aquece experts/mmap
#   3. 2 requests medidos (mesmo prompt → prompt cache zera o prefill;
#      medimos SÓ predicted_per_second) — reporta a MEDIANA
#   4. VRAM de pico amostrada a cada 2 s; acima do teto = OVER, OOM = FAIL
#
# Uso:
#   ./calibrate_moe.sh [--apply]
#   DRY=1 ./calibrate_moe.sh
#   MOE_MIB="1024 1536 2048"  MOE_SHARE="0.25 0.5 1.0"
#   CAL_GGUF=... CAL_NCMOE=44 CAL_EXTRA_SERVING="..." (receita de outra entry)
#
# Resultado: results/calib-moe.csv (acumula; colunas mib,share,decode_tps,...)
# NOTA: --apply grava as flags vencedoras na entry MOE_ENTRY do config.yaml.
# ============================================================================
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)
RESULTS=benchmarks/results
mkdir -p "$RESULTS"

PORT=${CAL_PORT:-18081}
REPS=${CAL_REPS:-2}
PROMPT_TOK=${CAL_PROMPT:-512}
VRAM_CEIL=${CAL_VRAM_CEIL:-11700}
GRID_MIB=${MOE_MIB:-"1024 1536 2048"}
GRID_SHARE=${MOE_SHARE:-"0.5 1.0"}
DRY=${DRY:-0}
APPLY=0
for a in "$@"; do [ "$a" = "--apply" ] && APPLY=1; done

# --- Receita de serving (default: Qwen3.8_Flash_Next_Abl_Q2_0) -------------
ENTRY=${MOE_ENTRY:-Qwen3.8_Flash_Next_Abl_Q2_0}
IMG=${CAL_IMG:-llama.cpp-pdcache:latest}
GGUF=${CAL_GGUF:-Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF/Q2_0/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-Q2_0-00001-of-00002.gguf}
NCMOE=${CAL_NCMOE:-44}
LMODE=${CAL_LMODE:-"-lm mmap+mlock --lazy-mode on"}
THREADS=${CAL_THREADS:-16}
BSZ=${CAL_B:-4096}
UB=${CAL_UB:-2048}
BASE_FLAGS=${CAL_EXTRA_SERVING:-""}   # p.ex. draft/MTP da receita real

OUT="$RESULTS/calib-moe-${PROMPT_TOK}tok.csv"
ERR="$RESULTS/calib-moe-${PROMPT_TOK}tok.errors.log"
[ -f "$OUT" ] || echo "entry,mib,share,decode_tps,decode2_tps,load_s,vram_peak_mib,status" > "$OUT"

prompt_for() { # $1=alvo tokens, $2=seed
  python3 - "$1" "$2" <<'EOF'
import sys, random
target, off = int(sys.argv[1]), int(sys.argv[2])
random.seed(target * 7919 + off)
words = ("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo "
         "lima mike november oscar papa quebec romeo sierra tango uniform "
         "victor whiskey xray yankee zulu linha casa poço torre nuvem ponte "
         "laranja teclado janela mercado cavalo estrela caminho violão").split()
out = []; n = 0
while n < target:
    w = random.choice(words); out.append(w); n += len(w) // 3 + 1
print(" ".join(out))
EOF
}

decode_req() { # $1=prompt -> imprime predicted_per_second
  python3 - "$1" "$PORT" <<'EOF'
import json, sys, urllib.request
prompt, port = sys.argv[1], int(sys.argv[2])
body = {"prompt": prompt, "n_predict": 256, "temperature": 0, "cache_prompt": True}
r = urllib.request.Request(f"http://127.0.0.1:{port}/completion",
    data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
try:
    t = json.load(urllib.request.urlopen(r, timeout=600))["timings"]
    print(t["predicted_per_second"])
except Exception:
    print(0)
EOF
}

run_combo() { # $1=mib $2=share (share ignorado se mib=0)
  local mib=$1 share=$2
  local cname="calibmoe-${ENTRY//./-}"
  local -a cmd=(docker run --rm --name "$cname" --gpus all --ulimit memlock=-1
    --entrypoint /usr/local/bin/llama-server
    -p "127.0.0.1:${PORT}:8080" -v "$ROOT/models:/models"
    -v /tmp/opencode/pdcache-calib:/kvcache
    "$IMG"
    --host 0.0.0.0 --port 8080 -fa on --jinja -np 1 -t "$THREADS"
    -ctk q4_0 -ctv q4_0 --cache-reuse 256 --cache-ram 1024
    --slot-save-path /kvcache
    -m "/models/${GGUF}"
    ${LMODE}
    -c 131072 -ngl 99 -ncmoe "${NCMOE}" -b "$BSZ" -ub "$UB")
  [ "$mib" != "0" ] && cmd+=(--moe-cache-mib "$mib" --moe-cache-cpu-share "$share")
  [ -n "$BASE_FLAGS" ] && cmd+=(${BASE_FLAGS})

  echo "[calib-moe] $ENTRY mib=$mib share=$share" >&2
  if [ "$DRY" = 1 ]; then echo "  DRY: ${cmd[*]}" >&2; return 0; fi

  "${cmd[@]}" > "$RESULTS/.calibmoe-${mib}-${share}.server.log" 2>&1 &
  local spid=$!
  local vfile; vfile=$(mktemp)
  ( local_max=0
    while kill -0 "$spid" 2>/dev/null; do
      v=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
      [ -n "$v" ] && [ "$v" -gt "$local_max" ] && local_max=$v
      sleep 2
    done
    echo "$local_max" > "$vfile" ) &
  local sampler=$!

  local up=0 t0=$(date +%s)
  for i in $(seq 1 120); do
    curl -sf -m 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 && { up=1; break; }
    sleep 3
  done
  local load_s=$(( $(date +%s) - t0 ))
  if [ "$up" != 1 ]; then
    echo "$(date +%F' '%T) FALHA carga mib=$mib share=$share (${load_s}s)" >> "$ERR"
    echo "$ENTRY,$mib,$share,0,0,$load_s,0,FAIL" >> "$OUT"
    kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null; wait "$sampler" 2>/dev/null
    rm -f "$vfile"; docker rm -f "$cname" >/dev/null 2>&1
    return 0
  fi

  # warm-up curto (n_predict=8) — aquece mmap/experts, não conta
  local p; p=$(prompt_for "$PROMPT_TOK" 99)
  python3 - "$p" "$PORT" <<'EOF' >/dev/null 2>&1
import json, sys, urllib.request
prompt, port = sys.argv[1], int(sys.argv[2])
body = {"prompt": prompt, "n_predict": 8, "temperature": 0, "cache_prompt": True}
r = urllib.request.Request(f"http://127.0.0.1:{port}/completion",
    data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
urllib.request.urlopen(r, timeout=600).read()
EOF

  local -a vals=()
  for r in $(seq 1 "$REPS"); do
    local tp; tp=$(decode_req "$p")
    vals+=("${tp:-0}")
    [ "$(python3 -c "print(1 if float('${tp:-0}') > 0 else 0)")" != 1 ] && \
      echo "$(date +%F' '%T) FALHA request mib=$mib share=$share rep=$r" >> "$ERR"
  done

  kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
  wait "$sampler" 2>/dev/null
  local vram; vram=$(cat "$vfile" 2>/dev/null); [ -z "$vram" ] && vram=0
  rm -f "$vfile"

  local status=OK
  [ "$(python3 -c "print(1 if float('${vals[0]:-0}') <= 0 else 0)")" = 1 ] && status=FAIL
  [ "$status" = OK ] && [ "$vram" -gt "$VRAM_CEIL" ] && status=OVER
  echo "$ENTRY,$mib,$share,${vals[0]%.*},${vals[1]:-${vals[0]}%.*},$load_s,$vram,$status" >> "$OUT"
  echo "[calib-moe]   -> decode ${vals[0]%.*} t/s (rep2 ${vals[1]:-${vals[0]}}) | VRAM $vram MiB | carga ${load_s}s | $status" >&2
  docker rm -f "$cname" >/dev/null 2>&1
}

echo "[calib-moe] entry=$ENTRY gguf=$GGUF mib=[$GRID_MIB] share=[$GRID_SHARE] teto=${VRAM_CEIL}MiB" >&2

run_combo 0 0  # baseline sem cache
for mib in $GRID_MIB; do
  for share in $GRID_SHARE; do
    run_combo "$mib" "$share"
  done
done

[ "$DRY" = 1 ] && exit 0

echo "" >&2
python3 - "$OUT" "$VRAM_CEIL" "$ENTRY" <<'EOF'
import csv, sys
out, ceil, entry = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = [r for r in csv.DictReader(open(out)) if r['entry'] == entry]
ok = [r for r in rows if r['status'] in ('OK', 'OVER') and float(r['decode_tps']) > 0]
if not ok:
    print('NENHUM combo válido — ver', out); sys.exit(1)
ok.sort(key=lambda r: -float(r['decode_tps']))
print(f"{'mib':>6} {'share':>6} {'decode t/s':>11} {'rep2':>7} {'VRAM MiB':>9} {'carga s':>8}  status")
for r in ok:
    print(f"{r['mib']:>6} {r['share']:>6} {float(r['decode_tps']):>11.1f} {r['decode2_tps']:>7} {r['vram_peak_mib']:>9} {r['load_s']:>8}  {r['status']}")
win = next(r for r in ok if r['status'] == 'OK')
base = next((r for r in ok if r['mib'] == '0'), None)
delta = ""
if base:
    d = (float(win['decode_tps']) / float(base['decode_tps']) - 1) * 100
    delta = f" ({d:+.1f}% vs baseline)"
print(f"\nVENCEDOR: --moe-cache-mib {win['mib']} --moe-cache-cpu-share {win['share']}"
      f" → {float(win['decode_tps']):.1f} tok/s @ VRAM {win['vram_peak_mib']} MiB{delta}")
EOF

if [ "$APPLY" = 1 ]; then
  WIN=$(python3 -c "
import csv,sys
rows=[r for r in csv.DictReader(open('$OUT')) if r['entry']=='$ENTRY' and r['status']=='OK' and float(r['decode_tps'])>0]
w=max(rows,key=lambda r: float(r['decode_tps']))
print(f'--moe-cache-mib {w[\"mib\"]} --moe-cache-cpu-share {w[\"share\"]}' if w['mib']!='0' else '')" 2>/dev/null || true)
  echo "[calib-moe] --apply: entry $ENTRY → flags: '${WIN:-<nenhuma — remover flags>}'" >&2
  echo "Edite o config.yaml manualmente ou confirme para eu aplicar." >&2
fi
