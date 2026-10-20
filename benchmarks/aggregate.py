#!/usr/bin/env python3
"""aggregate.py — consolida os resultados dos benchmarks em datasets tidy.

Uso:  python3 benchmarks/aggregate.py

Saídas em benchmarks/results/:
  e2e.csv      — sweep llama-server: entry, target_ctx, prompt_n (contexto
                 cheio), prefill_tps, decode_tps, prefill_s (tempo para
                 processar), decode_s, total_s, vram_peak_mib
  pp3d.csv     — llama-bench: superfície batch × ubatch → prefill tok/s
  summary.md   — resumo legível
Pode rodar com a suite ainda em andamento (consolida o parcial).
"""
import sys
from pathlib import Path

import pandas as pd

RESULTS = Path(__file__).parent / "results"


def load_e2e() -> pd.DataFrame | None:
    rows = []
    for f in sorted(RESULTS.glob("*__e2e.csv")):
        entry = f.stem.rsplit("__", 1)[0]
        try:
            df = pd.read_csv(f)
        except Exception as e:
            print(f"[skip] {f.name}: {e}", file=sys.stderr)
            continue
        df["entry"] = entry
        vram = RESULTS / f".vram_{entry}"
        df["vram_peak_mib"] = int(vram.read_text().strip()) if vram.exists() else None
        rows.append(df)
    if not rows:
        return None
    return pd.concat(rows, ignore_index=True).sort_values(["entry", "target_ctx"])


def load_pp3d() -> pd.DataFrame | None:
    rows = []
    for f in sorted(RESULTS.glob("*__pp3d.csv")):
        entry = f.stem.rsplit("__", 1)[0]
        try:
            df = pd.read_csv(f)
        except Exception as e:
            print(f"[skip] {f.name}: {e}", file=sys.stderr)
            continue
        df["entry"] = entry
        rows.append(df)
    if not rows:
        return None
    return pd.concat(rows, ignore_index=True)


def main() -> None:
    e2e = load_e2e()
    if e2e is not None:
        e2e.to_csv(RESULTS / "e2e.csv", index=False)
        n = len(e2e)
        print(f"e2e.csv: {n} linhas, {e2e['entry'].nunique()} modelos")
        print(e2e.to_string(index=False))
    else:
        print("e2e: sem dados ainda")

    pp3d = load_pp3d()
    if pp3d is not None:
        cols = ["entry", "n_batch", "n_ubatch", "n_prompt", "avg_ts", "stddev_ts"]
        pp3d[cols].to_csv(RESULTS / "pp3d.csv", index=False)
        print(f"\npp3d.csv: {len(pp3d)} linhas, {pp3d['entry'].nunique()} modelos")
    else:
        print("pp3d: sem dados ainda")


if __name__ == "__main__":
    main()
