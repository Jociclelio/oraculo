#!/usr/bin/env python3
# ============================================================================
# benchmarks/plot_ctx.py — gráfico do sweep decode×contexto (sweep_ctx.py)
#
# 3 curvas por entry:
#   - Decode (t/s)      → régua no EIXO Y ESQUERDO
#   - Prefill (t/s)     → régua no EIXO Y DIREITO
#   - IZ (índice 0-100) → eixo NO MEIO do gráfico, com linhas de referência
#                         horizontais em iz = 25 / 50 / 75 / 100
#
# Uso:
#   python3 benchmarks/plot_ctx.py <entry> [entry2 ...]   # results/ctxsweep/
#   python3 benchmarks/plot_ctx.py --all                  # todas as entries
# Saída: results/plots/ctxsweep/<entry>__ctx.png
# ============================================================================
import json, os, sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "results", "ctxsweep")
OUT = os.path.join(HERE, "results", "plots", "ctxsweep")

IZ_REFS = [25, 50, 75, 100]

C_DEC, C_PRE, C_IZ = "#1f77b4", "#d62728", "#2ca02c"


def plot_entry(entry):
    path = os.path.join(SRC, f"{entry}__ctxsweep.json")
    if not os.path.exists(path):
        print(f"[skip] {entry}: {path} não encontrado")
        return
    with open(path) as f:
        pts = json.load(f)["points"]
    x = [p["prompt_tokens"] / 1024 for p in pts]
    dec = [p["decode_tps"] for p in pts]
    pre = [p["prefill_tps"] for p in pts]
    iz = [p["iz"] for p in pts]

    fig, ax1 = plt.subplots(figsize=(11, 6))
    fig.subplots_adjust(wspace=0)

    # eixo ESQUERDO — decode
    ax1.plot(x, dec, color=C_DEC, marker="o", ms=4, lw=1.8, label="Decode (t/s)")
    ax1.set_xlabel("Contexto (k tokens)")
    ax1.set_ylabel("Decode (t/s)", color=C_DEC)
    ax1.tick_params(axis="y", labelcolor=C_DEC)
    ymax = max(max(dec), max(iz)) * 1.15
    ax1.set_ylim(0, ymax)
    ax1.grid(True, alpha=0.25)

    # eixo DIREITO — prefill
    ax2 = ax1.twinx()
    ax2.plot(x, pre, color=C_PRE, marker="s", ms=4, lw=1.8, label="Prefill (t/s)")
    ax2.set_ylabel("Prefill (t/s)", color=C_PRE)
    ax2.tick_params(axis="y", labelcolor=C_PRE)
    ax2.set_ylim(0, max(pre) * 1.15)

    # eixo do MEIO — IZ (régua própria, spine deslocada para o centro)
    ax3 = ax1.twinx()
    ax3.spines["right"].set_position(("axes", 0.5))
    ax3.spines["right"].set_visible(True)
    ax3.spines["right"].set_color(C_IZ)
    ax3.plot(x, iz, color=C_IZ, marker="^", ms=4, lw=1.8, ls="--", label="IZ")
    ax3.set_ylabel("IZ (0–100)", color=C_IZ, labelpad=32)
    ax3.tick_params(axis="y", labelcolor=C_IZ, pad=6)
    ax3.set_ylim(0, 125)
    ax3.set_yticks([0, 25, 50, 75, 100])
    # linhas de referência do IZ atravessando o gráfico
    for v in IZ_REFS:
        ax3.axhline(v, color=C_IZ, alpha=0.35, lw=1, ls=":")
    ax3.set_zorder(ax2.zorder + 1)
    ax3.patch.set_visible(False)

    # legenda combinada
    h1, l1 = ax1.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    h3, l3 = ax3.get_legend_handles_labels()
    ax1.legend(h1 + h2 + h3, l1 + l2 + l3, loc="upper right", fontsize=9)

    ax1.set_title(f"{entry} — decode, prefill e IZ × contexto (sweep e2e, receita de serving)")
    fig.tight_layout()
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, f"{entry}__ctx.png")
    fig.savefig(out, dpi=140)
    plt.close(fig)
    print(f"OK: {out}")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--all":
        args = sorted(f[:-len("__ctxsweep.json")] for f in os.listdir(SRC)
                      if f.endswith("__ctxsweep.json"))
    if not args:
        sys.exit("uso: plot_ctx.py <entry> [--all]")
    for e in args:
        plot_entry(e)


if __name__ == "__main__":
    main()
