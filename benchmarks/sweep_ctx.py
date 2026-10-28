#!/usr/bin/env python3
# ============================================================================
# benchmarks/sweep_ctx.py — sweep decode×contexto (0→130k, ~8k) via llama-swap
#
# Bate no SERVING (:8081, receita do config.yaml — incl. MTP/draft, pdcache),
# então mede o desempenho real do zoo. Prompts crescem incrementalmente
# (texto real pt-BR) — o cache_n mostra o acerto do prompt cache entre pontos.
# IZ inline (iz.py). Saída: results/ctxsweep/<entry>__ctxsweep.json +
# consolidado results/ctxsweep__<data>.csv.
#
# Uso:
#   python3 benchmarks/sweep_ctx.py <entry1> [entry2 ...]
# ============================================================================
import csv, json, os, sys, time, urllib.request
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iz import d_norm, p_norm  # noqa: E402

BASE = os.environ.get("SWEEP_BASE", "http://localhost:8081")
N_GEN = 256
CTX = 131072
SAFE_MAX = CTX - N_GEN - 600
TARGETS = [min(t, CTX - N_GEN - 800) for t in range(0, 131073, 8192)]
HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "results", "ctxsweep")
CSVP = os.path.join(HERE, "results", f"ctxsweep__{date.today().isoformat()}.csv")

BLOCK = ("O servidor local processa requisições em fila única e devolve JSON "
         "estruturado. Cada camada do modelo aplica normalização, atenção "
         "multi-cabeça e projeção antes de seguir para o próximo bloco. O "
         "cache de contexto evita recomputar tokens já processados em turnos "
         "anteriores, e o agendador distribui os lotes entre os dispositivos "
         "disponíveis conforme a memória de cada um. Quando um arquivo muda, "
         "o índice é atualizado e os testes rodam de novo em sequência. ")
UNIT = BLOCK * 3
QUESTION = ("\n\nCom base em todo o texto acima, responda em uma única frase: "
            "quem atualiza o índice quando um arquivo muda?")
HEADER = "Você é um assistente de teste. Leia o texto a seguir com atenção.\n\n"


def sweep(model):
    points, filler, ratio, last_pt = [], "", 4.5, 0
    for target in TARGETS:
        need = target - last_pt
        add, est = "", 0.0
        while est < need:
            add += UNIT
            est = len(add) / ratio
        if last_pt + est > SAFE_MAX:
            add = UNIT * max(1, int(need * ratio / len(UNIT)))
        filler += add
        prompt = HEADER + filler + QUESTION
        req = urllib.request.Request(
            BASE + "/v1/chat/completions",
            data=json.dumps({"model": model,
                             "messages": [{"role": "user", "content": prompt}],
                             "max_tokens": N_GEN, "temperature": 0.0}).encode(),
            headers={"Content-Type": "application/json"})
        t0 = time.time()
        with urllib.request.urlopen(req, timeout=3600) as r:
            body = json.load(r)
        wall = time.time() - t0
        tg = body.get("timings", {})
        dn = tg.get("draft_n", 0)
        pt = body["usage"]["prompt_tokens"]
        ratio = len(prompt) / max(1, pt)
        last_pt = pt
        dec = tg.get("predicted_per_second", 0)
        pre = tg.get("prompt_per_second", 0)
        t_ing = pt / pre if pre > 0 else 0
        rec = {
            "depth_target": target, "prompt_tokens": pt,
            "gen_tokens": body["usage"]["completion_tokens"],
            "decode_tps": round(dec, 2), "prefill_tps": round(pre, 2),
            "cache_n": tg.get("cache_n", 0),
            "draft": f"{tg.get('draft_n_accepted', 0)}/{dn}",
            "draft_acc": round(tg.get("draft_n_accepted", 0) / dn, 3) if dn else None,
            "t_ingest_s": round(t_ing, 1),
            "iz": round(100.0 * min(d_norm(dec), p_norm(t_ing)), 1) if dec else None,
            "wall_s": round(wall, 1),
        }
        points.append(rec)
        print(f"[{model}] {json.dumps(rec)}", flush=True)
    return points


def main():
    entries = sys.argv[1:]
    if not entries:
        sys.exit("uso: sweep_ctx.py <entry1> [entry2 ...]")
    os.makedirs(OUTDIR, exist_ok=True)
    rows = []
    for i, entry in enumerate(entries, 1):
        print(f"\n=== [{i}/{len(entries)}] {entry} ===", flush=True)
        try:
            pts = sweep(entry)
        except Exception as e:
            print(f"[{entry}] ERRO: {e!r} — retry único em 15 s", flush=True)
            time.sleep(15)
            try:
                pts = sweep(entry)
            except Exception as e2:
                print(f"[{entry}] FALHA DEFINITIVA: {e2!r}", flush=True)
                continue
        with open(os.path.join(OUTDIR, f"{entry}__ctxsweep.json"), "w") as f:
            json.dump({"model": entry, "n_gen": N_GEN, "points": pts}, f, indent=1)
        rows.extend(pts)
        print(f"[{entry}] OK", flush=True)
    if rows:
        with open(CSVP, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print(f"consolidado: {CSVP}", flush=True)


if __name__ == "__main__":
    main()
