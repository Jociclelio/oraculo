#!/bin/bash
# ============================================================================
# benchmarks/calibrate.sh v1 — calibração automática de batch/ubatch (prefill)
#
# Varre a grade batch × ubatch subindo o llama-server na RECEITA DE SERVING
# da entry (mesmo método e2e do sweep: prompt real tokenizado, mmproj, KV
# q5_1/q5_1, ncmoe de serving) e elege o par (b,ub) com maior prefill tok/s
# dentro do teto de VRAM. Diferenças vs pp3d (llama-bench):
#   - medição e2e real (não -p sintético do llama-bench)
#   - sabe de VRAM: carga que estoura compute buffer = FAIL, pico acima do
#     teto = OVER (reportado, não eleito)
#   - sugere (e com --apply grava) a linha `-b X -ub Y` no config.yaml
#
# Uso:
#   ./calibrate.sh <entry>              # varre a grade e reporta o ótimo
#   ./calibrate.sh <entry> --apply      # aplica o vencedor no config.yaml
#   DRY=1 ./calibrate.sh <entry>        # só imprime os comandos
#   CAL_B="1024 2048 4096 8192" CAL_UB="512 1024 2048 4096"   # grades
#   CAL_PROMPT=8192   # tokens do prompt de medição
#   CAL_REPS=2        # requests por combo (prompts distintos — cache-reuse!)
#   CAL_VRAM_CEIL=11700   # MiB; pico acima = OVER (folga p/ desktop, regra 3)
#   CAL_EXTRA_FLAGS="..." # flags extras da receita real de serving (draft/MTP!)
#   CAL_PORT=18081
#
# Resultado: results/<entry>__calib.csv
#   entry,b,ub,prefill_tps,load_s,vram_peak_mib,status
#
# Custo: ~40-70 s por combo (carga do modelo domina; prompts quentes na
# page cache) — grade default 13 combos ≈ 12-18 min por entry.
#
# NOTAS DE MÉTODO:
#   - n_predict=1: mede SÓ prefill (decode não depende de b/ub — regra 7:
#     o gargalo MoE é a re-leitura de pesos de experts por ubatch).
#   - reps com prompts de seeds DIFERENTES: prompt repetido acionaria o
#     prompt cache de RAM e a 2ª medição sairia falsamente ~instantânea.
#   - Cada combo é um container novo → não há contaminação entre combos.
#   - Sem draft/MTP: irrelevante p/ prefill e economiza compute buffer.
# ============================================================================
set -u
cd "$(dirname "$0")/.."
RESULTS=benchmarks/results
mkdir -p "$RESULTS"

# Metadados das entries (GGUF/IMG/MOE/NCMOE/MMPROJ/KV/B/UB) de bench.sh,
# sem executar o main dele (guard BENCH_LIB).
BENCH_LIB=1 source benchmarks/bench.sh

PORT=${CAL_PORT:-18081}
PROMPT_TOK=${CAL_PROMPT:-8192}
REPS=${CAL_REPS:-2}
VRAM_CEIL=${CAL_VRAM_CEIL:-11700}
GRID_B=${CAL_B:-"1024 2048 4096 8192"}
GRID_UB=${CAL_UB:-"512 1024 2048 4096"}
DRY=${DRY:-0}

entry=${1:-}
[ -n "$entry" ] || { echo "uso: $0 <entry> [--apply]"; exit 1; }
APPLY=0
for a in "$@"; do [ "$a" = "--apply" ] && APPLY=1; done
[ -n "${GGUF[$entry]:-}" ] || { echo "entry desconhecida: $entry"; exit 1; }
[ -f "models/${GGUF[$entry]}" ] || { echo "GGUF ausente: models/${GGUF[$entry]}"; exit 1; }

OUT="$RESULTS/${entry}__calib.csv"
ERR="$RESULTS/${entry}__calib.errors.log"

# ---------------------------------------------------------------------------
# Prompt sintético — mesma receita do sweep (palavras variadas, seed por
# tamanho+offset: sem prefixo comum entre pontos/reps p/ não acionar cache)
# ---------------------------------------------------------------------------
prompt_for() { # $1=alvo tokens, $2=offset de seed
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

run_combo() { # $1=b $2=ub
  local b=$1 ub=$2
  local cname="calib-${entry//./-}"
  local -a cmd=(docker run --rm --name "$cname" --gpus all
    --entrypoint "$(entptr "${IMG[$entry]}")"
    -p "127.0.0.1:${PORT}:8080" -v "$ROOT/models:/models"
    "$(img_ref "${IMG[$entry]}")"
    --host 0.0.0.0 --port 8080 -fa on --jinja -np 1 -t 5
    -ctk "${KV[$entry]%%:*}" -ctv "${KV[$entry]##*:}"
    --cache-reuse 256
    -m "/models/${GGUF[$entry]}")
  [ -n "${MMPROJ[$entry]}" ] && cmd+=(--mmproj "/models/${MMPROJ[$entry]}")
  [ "${MOE[$entry]}" = 1 ] && cmd+=(--load-mode none -ncmoe "${NCMOE[$entry]}")
  # Flags extras da receita real de serving (ex.: "--spec-type draft-mtp
  # --spec-draft-n-max 2"): o draft consome compute buffer e muda o teto
  # de VRAM — medir SEM ele subestima a VRAM e pode eleger combo que OOMa
  # em produção (ex.: ub4096 só cabe sem draft no Qwen3.6 35B).
  [ -n "${CAL_EXTRA_FLAGS:-}" ] && cmd+=(${CAL_EXTRA_FLAGS})
  cmd+=(-c 131072 -ngl 99 -b "$b" -ub "$ub")

  echo "[calib] $entry b=$b ub=$ub" >&2
  if [ "$DRY" = 1 ]; then echo "  DRY: ${cmd[*]}" >&2; return 0; fi

  "${cmd[@]}" > "$RESULTS/.calib-${b}-${ub}.server.log" 2>&1 &
  local spid=$!

  # VRAM de pico durante o combo (amostra a cada 2 s)
  # SEM `local` dentro do subshell — local só vale em função; com local o
  # sampler morria silenciosamente e a VRAM saía vazia no CSV.
  local vfile; vfile=$(mktemp)
  ( local_max=0
    while kill -0 "$spid" 2>/dev/null; do
      v=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
      [ -n "$v" ] && [ "$v" -gt "$local_max" ] && local_max=$v
      sleep 2
    done
    echo "$local_max" > "$vfile" ) &
  local sampler=$!
  # NÃO matar o sampler manualmente: ele sai sozinho quando o server morre
  # (kill -0 falha) e é aí que o pico é escrito no vfile.

  # espera health (carga fria/quente do GGUF)
  local up=0 t0=$(date +%s)
  for i in $(seq 1 120); do
    curl -sf -m 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 && { up=1; break; }
    sleep 3
  done
  local load_s=$(( $(date +%s) - t0 ))
  if [ "$up" != 1 ]; then
    echo "$(date +%F' '%T) FALHA carga b=$b ub=$ub (${load_s}s)" >> "$ERR"
    echo "$entry,$b,$ub,0,$load_s,0,FAIL" >> "$OUT"
    kill "$sampler" 2>/dev/null; rm -f "$vfile"
    kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
    docker rm -f "$cname" >/dev/null 2>&1
    return 0
  fi

  # reps de prefill (n_predict=1); max entre reps
  local best=0 r
  for r in $(seq 1 "$REPS"); do
    local bodyfile; bodyfile=$(mktemp)
    prompt_for "$PROMPT_TOK" "$r" | python3 -c "
import json, sys
print(json.dumps({'prompt': sys.stdin.read(), 'n_predict': 1}))" > "$bodyfile"
    local pp
    pp=$(curl -s -m 900 "http://127.0.0.1:${PORT}/completion" \
      -H "Content-Type: application/json" -d @"$bodyfile" \
      | python3 -c "
import json, sys
try: print(json.load(sys.stdin)['timings']['prompt_per_second'])
except Exception: print(0)")
    rm -f "$bodyfile"
    if [ "$(python3 -c "print(1 if float('${pp:-0}') > 0 else 0)")" != 1 ]; then
      echo "$(date +%F' '%T) FALHA request b=$b ub=$ub rep=$r" >> "$ERR"
    fi
    [ "$(python3 -c "print(1 if float('${pp:-0}') > float('$best') else 0)")" = 1 ] && best=$pp
  done

  # Ordem IMPORTA: matar o servidor e ESPERAR o sampler sair sozinho — o
  # echo do pico só executa quando o loop termina (kill -0 falha após a
  # morte do server, até ~2s); matar o sampler antes = vfile vazio (=0).
  kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
  wait "$sampler" 2>/dev/null
  local vram; vram=$(cat "$vfile" 2>/dev/null)
  [ -z "$vram" ] && vram=0
  rm -f "$vfile"

  # best==0 (todas as reps falharam) NÃO é OK — é FAIL (flake ou ruído)
  local status=OK
  [ "$(python3 -c "print(1 if float('$best') <= 0 else 0)")" = 1 ] && status=FAIL
  [ "$status" = OK ] && [ "$vram" -gt "$VRAM_CEIL" ] && status=OVER
  echo "$entry,$b,$ub,${best%.*},$load_s,$vram,$status" >> "$OUT"
  echo "[calib]   -> ${best%.*} tok/s | VRAM $vram MiB | carga ${load_s}s | $status" >&2
  docker rm -f "$cname" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
echo "[calib] entry=$entry prompt=${PROMPT_TOK}tok reps=$REPS teto=${VRAM_CEIL}MiB" >&2
[ -f "$OUT" ] || echo "entry,b,ub,prefill_tps,load_s,vram_peak_mib,status" > "$OUT"

for b in $GRID_B; do
  for ub in $GRID_UB; do
    [ "$ub" -le "$b" ] || continue
    run_combo "$b" "$ub"
  done
done

[ "$DRY" = 1 ] && exit 0

# ---------------------------------------------------------------------------
# Relatório: ranking + vencedor dentro do teto
# ---------------------------------------------------------------------------
echo "" >&2
python3 - "$OUT" "$VRAM_CEIL" <<'EOF'
import csv, sys
rows = [r for r in csv.DictReader(open(sys.argv[1]))
        if r['entry'] != '' and r['b'] != 'b']
ceil = int(sys.argv[2])
ok = [r for r in rows if r['status'] in ('OK', 'OVER') and float(r['prefill_tps']) > 0]
if not ok:
    print('NENHUM combo válido — ver', sys.argv[1]); sys.exit(1)
ok.sort(key=lambda r: -float(r['prefill_tps']))
print(f"{'b':>6} {'ub':>6} {'prefill t/s':>12} {'VRAM MiB':>10} {'carga s':>8}  status")
for r in ok:
    print(f"{r['b']:>6} {r['ub']:>6} {float(r['prefill_tps']):>12.0f} {r['vram_peak_mib']:>10} {r['load_s']:>8}  {r['status']}")
win = next(r for r in ok if r['status'] == 'OK')
print(f"\nVENCEDOR (dentro do teto {ceil} MiB): -b {win['b']} -ub {win['ub']} "
      f"→ {float(win['prefill_tps']):.0f} tok/s @ VRAM {win['vram_peak_mib']} MiB")
EOF
WIN_B=$(python3 -c "
import csv,sys
rows=[r for r in csv.DictReader(open('$OUT')) if r.get('status')=='OK' and float(r['prefill_tps'])>0]
w=max(rows,key=lambda r: float(r['prefill_tps']))
print(w['b'],w['ub'])" 2>/dev/null || true)

if [ "$APPLY" = 1 ] && [ -n "$WIN_B" ]; then
  read -r WB WUB <<< "$WIN_B"
  python3 - "$entry" "$WB" "$WUB" llama-swap/config.yaml <<'EOF'
import re, sys
entry, b, ub, path = sys.argv[1:5]
src = open(path).read()
m = re.search(rf'(?ms)^  {re.escape(entry)}:\n(.*?)(?=^  \S|\Z)', src)
if not m:
    print(f"[apply] bloco da entry {entry} não encontrado"); sys.exit(1)
block = m.group(0)
new = re.sub(r'-b \d+ -ub \d+', f'-b {b} -ub {ub}', block)
if new == block:
    if re.search(r'-ub \d+', block):
        new = re.sub(r'-ub \d+', f'-ub {ub}', block)
    else:
        print(f"[apply] entry {entry} não tem -b/-ub para substituir — ajuste manual"); sys.exit(1)
if new == block:
    print(f"[apply] entry {entry} já está em -b {b} -ub {ub}"); sys.exit(0)
open(path, 'w').write(src[:m.start(0)] + new + src[m.end(0):])
print(f"[apply] {entry}: linha -b/-ub atualizada para `-b {b} -ub {ub}` em {path}")
EOF
  echo "[apply] LEMBRETE: ./manage.sh restart + regra do repo (docs: AGENTS.md/README/MODELS_INSTALL)"
fi
