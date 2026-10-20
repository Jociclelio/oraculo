#!/usr/bin/env python3
"""plot.py — os 4 gráficos de desempenho do zoológico.

Uso:  python3 benchmarks/plot.py     # PNGs em benchmarks/results/plots/

  1. decode_ctx.png   — decode (t/s) × quantidade de contexto cheio (0→128k)
  2. pp3d_<modelo>.png— superfície 3D batch × ubatch → prefill (t/s)
  3. pp_ctx.png       — prefill (t/s) × quantidade de contexto
  4. tempo_ctx.png    — tempo para processar (s) × quantidade de contexto

Requer benchmarks/aggregate.py rodado antes (gera results/e2e.csv e pp3d.csv).
"""
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

RESULTS = Path(__file__).parent / "results"
PLOTS = RESULTS / "plots"

LABEL = {
    "Qwen3.6_35B_General": "Qwen3.6-35B (General)",
    "Qwen3.6_35B_Code": "Qwen3.6-35B (Code)",
    "Qwen3.6_35B_It_General": "Qwen3.6-35B (It)",
    "Qwen3.6_35B_It_Reasoning": "Qwen3.6-35B (It-R)",
    "Qwen3.6_35B_A3B_Hauhau_Aggressive": "Qwen3.6-35B (Hauhau)",
    "Ornith1.5_35B_MTP": "Ornith 1.5-35B",
    "LFM2.5_24B_A2B": "LFM2.5-24B",
    "Qwen3.8_35B_Distill": "Qwen3.8-35B-Distill",
    "MiniCPM-V_4.7_35B": "MiniCPM-V 4.7-35B",
    "Gemma4_12B": "Gemma4-12B",
    "bonsai-27b": "Bonsai2-27B",
    "Xing4.0_29B_A4B": "Xing4.0-29B",
}


def short(e: str) -> str:
    return LABEL.get(e, e)


def main() -> None:
    PLOTS.mkdir(parents=True, exist_ok=True)
    e2e_f = RESULTS / "e2e.csv"
    pp3d_f = RESULTS / "pp3d.csv"
    if not e2e_f.exists() and not pp3d_f.exists():
        sys.exit("sem results/e2e.csv nem results/pp3d.csv — rode aggregate.py")

    # ---------------------------------------------------------------
    # 1. decode × contexto cheio (e2e)
    # ---------------------------------------------------------------
    if e2e_f.exists():
        d = pd.read_csv(e2e_f)
        d = d[d["decode_tps"] > 0]
        fig, ax = plt.subplots(figsize=(9.5, 5.5))
        for key, g in d.groupby("entry"):
            g = g.sort_values("prompt_n")
            ax.plot(g["prompt_n"] / 1024, g["decode_tps"], marker="o", label=short(key))
        ax.set_title("Decode × contexto cheio (KV q5_1/q5_1, receita de serving)")
        ax.set_xlabel("tokens no contexto (k)")
        ax.set_ylabel("decode (tokens/s)")
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=8)
        fig.tight_layout()
        fig.savefig(PLOTS / "decode_ctx.png", dpi=130)
        plt.close(fig)
        print("  decode_ctx.png")

        # -----------------------------------------------------------
        # 3. prefill × contexto
        # -----------------------------------------------------------
        d = pd.read_csv(e2e_f)
        d = d[d["prefill_tps"] > 0]
        fig, ax = plt.subplots(figsize=(9.5, 5.5))
        for key, g in d.groupby("entry"):
            g = g.sort_values("prompt_n")
            ax.plot(g["prompt_n"] / 1024, g["prefill_tps"], marker="o", label=short(key))
        ax.set_title("Prefill × contexto")
        ax.set_xlabel("tokens no contexto (k)")
        ax.set_ylabel("prefill (tokens/s)")
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=8)
        fig.tight_layout()
        fig.savefig(PLOTS / "pp_ctx.png", dpi=130)
        plt.close(fig)
        print("  pp_ctx.png")

        # -----------------------------------------------------------
        # 4. tempo para processar × contexto
        # -----------------------------------------------------------
        fig, ax = plt.subplots(figsize=(9.5, 5.5))
        for key, g in d.groupby("entry"):
            g = g.sort_values("prompt_n")
            ax.plot(g["prompt_n"] / 1024, g["prefill_s"], marker="o", label=short(key))
        ax.set_title("Tempo para processar o contexto (prefill)")
        ax.set_xlabel("tokens no contexto (k)")
        ax.set_ylabel("tempo de prefill (s)")
        ax.set_yscale("log")
        ax.grid(True, alpha=0.3, which="both")
        ax.legend(fontsize=8)
        fig.tight_layout()
        fig.savefig(PLOTS / "tempo_ctx.png", dpi=130)
        plt.close(fig)
        print("  tempo_ctx.png")

    # ---------------------------------------------------------------
    # 2. superfície 3D batch × ubatch → prefill (llama-bench)
    # ---------------------------------------------------------------
    if pp3d_f.exists():
        d = pd.read_csv(pp3d_f)
        for entry, g in d.groupby("entry"):
            g = g[(g["n_prompt"] > 0) & (g["n_ubatch"] <= g["n_batch"])]
            piv = g.pivot_table(index="n_batch", columns="n_ubatch",
                                values="avg_ts", aggfunc="mean")
            if piv.empty:
                continue
            fig = plt.figure(figsize=(9, 6.5))
            ax = fig.add_subplot(projection="3d")
            X, Y = [], []
            Z = []
            for b, row in piv.iterrows():
                for ub, z in row.items():
                    if pd.isna(z):
                        continue
                    X.append(b)
                    Y.append(ub)
                    Z.append(z)
            ax.plot_trisurf(X, Y, Z, cmap="viridis", edgecolor="k", alpha=0.85)
            ax.set_xlabel("batch")
            ax.set_ylabel("ubatch")
            ax.set_zlabel("prefill (t/s)")
            ax.set_title(f"Prefill: batch × ubatch — {short(entry)} (p=8192)")
            fig.tight_layout()
            out = PLOTS / f"pp3d_{entry.replace('.', '_')}.png"
            fig.savefig(out, dpi=130)
            plt.close(fig)
            print(f"  pp3d_{entry.replace('.', '_')}.png")

    print(f"OK — gráficos em {PLOTS}/")


if __name__ == "__main__":
    main()
