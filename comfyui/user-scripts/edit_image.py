#!/usr/bin/env python3
"""Edição de imagem no ComfyUI (Qwen-Image 2.1 Turbo) via API — caminho do gpu-shim.

Usa o workflow API versionado (comfyui/workflows/qwen_image_2_1_turbo_edit_api.json)
e SEMPRE a porta 8188 (gpu-shim) — nunca 8189 (núcleo direto), senão a liberação
automática de VRAM (POST /free + unload do llama-swap, regra 8) não roda.

A 1ª imagem é a editada (define o canvas); as demais são referências
endereçáveis no prompt como <image2>..<image10> (até 10 imagens).

Uso:
  edit_image.py --image foto.png --prompt "make the mug white" [--seed N]
                [--steps 8] [--prefix pi-edit] [--ref extra.png --ref outra.png]

Saída: imprime o caminho do PNG editado em /tmp/oraculo-comfyui/output/ (volátil —
some no reboot).
"""
import argparse
import json
import mimetypes
import random
import sys
import time
import urllib.request
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WORKFLOW = REPO / "comfyui/workflows/qwen_image_2_1_turbo_edit_api.json"
OUTPUT_DIR = Path("/tmp/oraculo-comfyui/output")
BASE_URL = "http://127.0.0.1:8188"  # gpu-shim (NUNCA :8189)

# Nó 5 = imagem editada; nós 10-18 = referências 2-10
PRIMARY_NODE = "5"
REF_NODES = ["10", "11", "12", "13", "14", "15", "16", "17", "18"]


def api(path, payload=None, timeout=60):
    req = urllib.request.Request(
        BASE_URL + path,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Content-Type": "application/json"},
    )
    return json.load(urllib.request.urlopen(req, timeout=timeout))


def upload_image(path: Path) -> str:
    """Upload multipart para /upload/image; retorna o valor do input LoadImage."""
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    boundary = uuid.uuid4().hex
    body = bytearray()
    body.extend(
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="image"; filename="{path.name}"\r\n'
        f"Content-Type: {mime}\r\n\r\n".encode()
    )
    body.extend(path.read_bytes())
    body.extend(
        f"\r\n--{boundary}\r\n"
        f'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n'
        f"--{boundary}--\r\n".encode()
    )
    req = urllib.request.Request(
        BASE_URL + "/upload/image",
        data=bytes(body),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    r = json.load(urllib.request.urlopen(req, timeout=120))
    subfolder, name = r.get("subfolder", ""), r["name"]
    return f"{subfolder}/{name}" if subfolder else name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True, action="append", dest="images",
                    help="imagem a editar (1ª) e referências extras (repetível)")
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--negative", default="")
    ap.add_argument("--steps", type=int, default=8)
    ap.add_argument("--seed", default=None, help="inteiro ou vazio = aleatório")
    ap.add_argument("--prefix", default="edit")
    args = ap.parse_args()

    images = [Path(p).expanduser().resolve() for p in args.images]
    for p in images:
        if not p.is_file():
            print(f"ERRO: imagem não encontrada: {p}", file=sys.stderr)
            return 1
    if len(images) > 1 + len(REF_NODES):
        print(f"ERRO: máximo de {1 + len(REF_NODES)} imagens", file=sys.stderr)
        return 1

    seed = random.randint(0, 2**48) if args.seed is None else int(args.seed)

    wf = json.loads(WORKFLOW.read_text())
    wf[PRIMARY_NODE]["inputs"]["image"] = upload_image(images[0])
    for node, p in zip(REF_NODES, images[1:]):
        wf[node]["inputs"]["image"] = upload_image(p)
    wf["6"]["inputs"]["prompt"] = args.prompt
    if args.negative:
        wf["6"]["inputs"]["negative_prompt"] = args.negative
    wf["7"]["inputs"]["steps"] = args.steps
    wf["7"]["inputs"]["seed"] = seed
    wf["9"]["inputs"]["filename_prefix"] = args.prefix

    before = {p.name for p in OUTPUT_DIR.rglob("*.png")}
    r = api("/prompt", {"prompt": wf})
    pid = r["prompt_id"]
    print(f"prompt_id: {pid} (seed {seed})", file=sys.stderr)

    deadline = time.time() + 1800  # turbo 8 passos ~ 60 s quente; carga FRIA do DiT/TE
    # (pós-boot/pos-recreate) pode levar >10 min — folga larga
    while time.time() < deadline:
        hist = api(f"/history/{pid}", timeout=30)
        if pid in hist:
            outs = hist[pid].get("outputs", {})
            for node_out in outs.values():
                for img in node_out.get("images", {}):
                    name = img["filename"]
                    path = OUTPUT_DIR / img.get("subfolder", "") / name
                    if name not in before or path.exists():
                        if path.exists():
                            print(path)
                            return 0
            if hist[pid].get("status", {}).get("status_str") == "error":
                print("ERRO: execução falhou no ComfyUI", file=sys.stderr)
                return 1
        time.sleep(1)
    print("ERRO: timeout esperando a edição", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
