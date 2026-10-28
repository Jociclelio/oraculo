#!/usr/bin/env python3
# ============================================================================
# benchmarks/probe_depth.py — probe de profundidade p/ tuning de variantes
#
# Em vez do sweep completo (~10 min/variante), mede só 3 pontos (8k/64k/130k)
# por variante de configuração (~3-4 min cada): decode, prefill, aceitação do
# draft e VRAM de pico. Compara a RAZÃO DE PLANURA dec@130k / dec@8k.
# Replica a receita de serving da entry (imagem pdcache + flags) e injeta os
# flags extra da variante por cima (último valor vence no llama-server).
#
# Uso:
#   python3 benchmarks/probe_depth.py                    # bateria default
#   PROBE_VARIANTS="base n1 n3" python3 benchmarks/probe_depth.py
#   DRY=1 python3 benchmarks/probe_depth.py              # só imprime comandos
# Saída: results/probe_depth__<data>.csv + resumo no stdout
# ============================================================================
import csv, json, os, subprocess, sys, threading, time, urllib.error, urllib.request
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RESULTS = os.path.join(HERE, "results")
PORT = 18080
BASE = f"http://127.0.0.1:{PORT}"
N_GEN = 256
TARGETS = [8192, 65536, 130016]

MODEL = "/models/unsloth_Qwen3.6_35B_A3B_MTP/Qwen3.6-35B-A3B-MTP-Q4_K_M.gguf"
MMPROJ = "/models/unsloth_Qwen3.6_35B_A3B_MTP/mmproj-F16.gguf"
IMAGE = "llama.cpp-pdcache:latest"

# Receita de serving da entry Qwen3.6_35B_A3B (config.yaml), SEM os flags que
# as variantes sobrescrevem (n-max, ncmoe, spec-type, p-min).
BASE_CMD = [
    "docker", "run", "--rm", "--name", "probe-qwen36", "--gpus", "all",
    "--entrypoint", "/usr/local/bin/llama-server",
    "-p", f"127.0.0.1:{PORT}:8080",
    "-v", f"{ROOT}/models:/models",
    IMAGE,
    "--host", "0.0.0.0", "--port", "8080",
    "-fa", "on", "--jinja", "-np", "1", "-t", "5",
    "-ctk", "q4_0", "-ctv", "q4_0",
    "--cache-reuse", "256",
    "-m", MODEL, "--mmproj", MMPROJ,
    "--load-mode", "none",
    "--spec-type", "draft-mtp",
    "-c", "131072", "-ngl", "99", "-ncmoe", "33",
    "-b", "4096", "-ub", "2048",
]

VARIANTS = {
    "base":     ["--spec-draft-n-max", "2"],
    "n1":       ["--spec-draft-n-max", "1"],
    "n3":       ["--spec-draft-n-max", "3"],
    "pmin50":   ["--spec-draft-n-max", "2", "--spec-draft-p-min", "0.5"],
    "pmin70":   ["--spec-draft-n-max", "2", "--spec-draft-p-min", "0.7"],
    "pmin50n3": ["--spec-draft-n-max", "3", "--spec-draft-p-min", "0.5"],
    "ncmoe32":  ["--spec-draft-n-max", "2", "-ncmoe", "32"],
    "combo":    ["--spec-draft-n-max", "3", "--spec-draft-p-min", "0.5",
                 "-ncmoe", "32"],
    "ngram":    ["--spec-draft-n-max", "2",
                 "--spec-type", "draft-mtp,ngram-simple"],
}

# mesmo gerador de texto do sweep_ctx.py (comparabilidade direta)
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


def vram_now():
    out = subprocess.run(
        ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
        capture_output=True, text=True).stdout.strip().splitlines()
    return int(out[0]) if out else 0


def probe_variant(name, extra, rows, dry=False):
    cmd = BASE_CMD + extra
    if dry:
        print(f"[{name}] DRY: {' '.join(cmd)}")
        return True
    print(f"[{name}] server up: {' '.join(extra)}", flush=True)
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    up = False
    try:
        for _ in range(150):
            try:
                urllib.request.urlopen(f"{BASE}/health", timeout=2)
                up = True
                break
            except urllib.error.HTTPError as e:
                time.sleep(3)  # 503 "Loading model" — segue esperando
            except Exception:
                time.sleep(3)
        if not up:
            print(f"[{name}] FAIL: server não subiu (carga abortou?)")
            return False

        peak = [0]
        stop = [False]

        def sampler():
            while not stop[0]:
                peak[0] = max(peak[0], vram_now())
                time.sleep(2)
        import threading
        th = threading.Thread(target=sampler, daemon=True)
        th.start()

        filler, ratio, last_pt = "", 4.5, 0
        for target in TARGETS:
            need = target - last_pt
            add, est = "", 0.0
            while est < need:
                add += UNIT
                est = len(add) / ratio
            filler += add
            prompt = HEADER + filler + QUESTION
            req = urllib.request.Request(
                BASE + "/v1/chat/completions",
                data=json.dumps({"model": "x",
                                 "messages": [{"role": "user", "content": prompt}],
                                 "max_tokens": N_GEN, "temperature": 0.0}).encode(),
                headers={"Content-Type": "application/json"})
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=1200) as r:
                body = json.load(r)
            wall = time.time() - t0
            tg = body.get("timings", {})
            pt = body["usage"]["prompt_tokens"]
            ratio = len(prompt) / max(1, pt)
            last_pt = pt
            dn = tg.get("draft_n", 0)
            rec = {
                "variant": name, "depth_target": target, "prompt_tokens": pt,
                "decode_tps": round(tg.get("predicted_per_second", 0), 2),
                "prefill_tps": round(tg.get("prompt_per_second", 0), 2),
                "draft": f"{tg.get('draft_n_accepted', 0)}/{dn}",
                "draft_acc": round(tg.get("draft_n_accepted", 0) / dn, 3) if dn else None,
                "vram_mib": "",
            }
            rows.append(rec)
            print(f"[{name}] {json.dumps(rec)}", flush=True)
        stop[0] = True
        th.join(timeout=3)
        for rec in rows:
            if rec["variant"] == name:
                rec["vram_mib"] = peak[0]
        print(f"[{name}] OK (VRAM pico {peak[0]} MiB)", flush=True)
        return True
    except Exception as e:
        print(f"[{name}] ERRO: {e!r}", flush=True)
        return False
    finally:
        stop = None
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()
        subprocess.run(["docker", "rm", "-f", "probe-qwen36"],
                       capture_output=True)


def main():
    dry = os.environ.get("DRY") == "1"
    sel = os.environ.get("PROBE_VARIANTS", "").split()
    names = sel or list(VARIANTS)
    os.makedirs(RESULTS, exist_ok=True)
    rows = []
    for name in names:
        if name not in VARIANTS:
            sys.exit(f"variante desconhecida: {name}")
        probe_variant(name, VARIANTS[name], rows, dry)
    if dry or not rows:
        return
    out = os.path.join(RESULTS, f"probe_depth__{date.today().isoformat()}.csv")
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"\nconsolidado: {out}\n")

    # resumo: planura = dec@130k / dec@8k
    print(f"{'variante':<10} {'dec@8k':>7} {'dec@64k':>8} {'dec@130k':>9} "
          f"{'planura':>8} {'acc@130k':>9} {'VRAM':>6}")
    print("-" * 65)
    for name in names:
        pts = {r["depth_target"]: r for r in rows if r["variant"] == name}
        if len(pts) < 3:
            continue
        d8 = pts[8192]["decode_tps"]
        d64 = pts[65536]["decode_tps"]
        d130 = pts[130016]["decode_tps"]
        acc = pts[130016]["draft_acc"]
        vram = max(int(r["vram_mib"] or 0) for r in pts.values())
        print(f"{name:<10} {d8:>7.1f} {d64:>8.1f} {d130:>9.1f} "
              f"{d130/d8:>8.2f} {acc if acc is not None else float('nan'):>9.2f} "
              f"{vram:>6}")


if __name__ == "__main__":
    main()
