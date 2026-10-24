#!/usr/bin/env python3
"""Geração de imagem no ComfyUI (Qwen-Image 2.1 Turbo) via API — caminho do gpu-shim.

Usa o workflow API versionado (comfyui/workflows/qwen_image_2_1_turbo_t2i_api.json)
e SEMPRE a porta 8188 (gpu-shim) — nunca 8189 (núcleo direto), senão a liberação
automática de VRAM (POST /free + unload do llama-swap, regra 8) não roda.

Uso:
  generate_image.py --prompt "um gato astronauta" [--size 1024x1024]
                    [--steps 8] [--seed ALEATORIO] [--prefix minhaprefix]

Saída: imprime o caminho do PNG gerado em comfyui/output/.
"""
import argparse
import json
import random
import sys
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WORKFLOW = REPO / "comfyui/workflows/qwen_image_2_1_turbo_t2i_api.json"
OUTPUT_DIR = REPO / "comfyui/output"
BASE_URL = "http://127.0.0.1:8188"  # gpu-shim (NUNCA :8189)


def api(path, payload=None, timeout=60):
    req = urllib.request.Request(
        BASE_URL + path,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Content-Type": "application/json"},
    )
    return json.load(urllib.request.urlopen(req, timeout=timeout))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--negative", default="")
    ap.add_argument("--size", default="1024x1024")
    ap.add_argument("--steps", type=int, default=8)
    ap.add_argument("--seed", default=None, help="inteiro ou vazio = aleatório")
    ap.add_argument("--prefix", default="pi")
    args = ap.parse_args()

    w, h = (int(x) for x in args.size.lower().split("x"))
    seed = random.randint(0, 2**48) if args.seed is None else int(args.seed)

    wf = json.loads(WORKFLOW.read_text())
    wf["6"]["inputs"]["prompt"] = args.prompt
    if args.negative:
        wf["6"]["inputs"]["negative_prompt"] = args.negative
    wf["5"]["inputs"]["width"] = w
    wf["5"]["inputs"]["height"] = h
    wf["7"]["inputs"]["steps"] = args.steps
    wf["7"]["inputs"]["seed"] = seed
    wf["9"]["inputs"]["filename_prefix"] = args.prefix

    before = {p.name for p in OUTPUT_DIR.glob("*.png")}
    r = api("/prompt", {"prompt": wf})
    pid = r["prompt_id"]
    print(f"prompt_id: {pid} (seed {seed})", file=sys.stderr)

    deadline = time.time() + 600  # turbo 8 passos ~ 10-20 s; folga p/ carga fria do DiT
    while time.time() < deadline:
        hist = api(f"/history/{pid}", timeout=30)
        if pid in hist:
            outs = hist[pid].get("outputs", {})
            for node_out in outs.values():
                for img in node_out.get("images", {}):
                    name = img["filename"]
                    if name not in before or "output" in img.get("type", "output"):
                        path = OUTPUT_DIR / name
                        if path.exists():
                            print(path)
                            return 0
            if hist[pid].get("status", {}).get("status_str") == "error":
                print("ERRO: execução falhou no ComfyUI", file=sys.stderr)
                return 1
        time.sleep(1)
    print("ERRO: timeout esperando a geração", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
