#!/usr/bin/env python3
# ============================================================================
# benchmarks/iz.py — IZ, Índice Zoo (métrica de desempenho 0-100+)
#
# Combina decode e ingestão da janela pelo elo mais fraco (min dos fatores):
# um modelo é tão usável quanto o pior dos dois eixos. Cada fator vira uma
# nota 0-1+ por interpolação piecewise com 3 âncoras de usabilidade, e a IZ
# extrapola acima do "excelente" (IZ > 100 = desempenho superior):
#
#   Decode  : 25 t/s = não usável | 50 t/s = confortável | 100 t/s = excelente
#   Ingestão: 320 s = não usável  | 128 s  = confortável |  32 s  = excelente
#             (t = ctx_tokens ÷ prefill_tps — janela PRÓPRIA do modelo)
#
# Propriedades: IZ ≥ 75 ⇔ decode ≥ 50 E ingestão ≤ 128 s (confortável nos
# dois); IZ ≥ 100 ⇔ decode ≥ 100 E ingestão ≤ 32 s; fator na zona não-usável
# derruba a nota para <25 — o outro fator não salva.
#
# Uso:
#   python3 benchmarks/iz.py                  # ranking a partir de iz-data.csv
#   python3 benchmarks/iz.py --markdown       # tabela markdown (p/ docs)
#   python3 benchmarks/iz.py --file OUT.csv   # outro arquivo de dados
#
# Dados: benchmarks/results/iz-data.csv — colunas entry,ctx,decode_tps,prefill_tps
# (medição e2e: decode = 200 tok @ctx curto; prefill = prompt sintético @2k;
# ver README.md seção IZ). Regenerar após cada sweep.
# ============================================================================
import argparse
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CSV = os.path.join(HERE, "results", "iz-data.csv")

# âncoras de usabilidade
DEC_USABLE, DEC_COMF, DEC_EXC = 25.0, 50.0, 100.0
T_USABLE, T_COMF, T_EXC = 320.0, 128.0, 32.0


def d_norm(d: float) -> float:
    """Nota 0-1+ do decode (t/s)."""
    if d <= DEC_USABLE:
        return 0.25 * d / DEC_USABLE
    if d <= DEC_COMF:
        return 0.25 + 0.5 * (d - DEC_USABLE) / (DEC_COMF - DEC_USABLE)
    if d <= DEC_EXC:
        return 0.75 + 0.25 * (d - DEC_COMF) / (DEC_EXC - DEC_COMF)
    return 1.0 + (d - DEC_EXC) / DEC_EXC


def p_norm(t: float) -> float:
    """Nota 0-1+ do tempo de ingestão da janela (s)."""
    if t >= T_USABLE:
        return 0.25 * T_USABLE / t
    if t >= T_COMF:
        return 0.75 - 0.5 * (t - T_COMF) / (T_USABLE - T_COMF)
    if t >= T_EXC:
        return 0.75 + 0.25 * (T_COMF - t) / (T_COMF - T_EXC)
    return 1.0 + (T_EXC - t) / T_EXC


def limitador(d: float, p: float) -> str:
    if abs(d - p) < 0.05:
        return "equilibrado"
    return "decode" if d < p else "prefill"


def leitura(iz: float, d: float, t: float) -> str:
    if d < DEC_USABLE or t > T_USABLE:
        return "não usável"
    if iz >= 100:
        return "superior"
    if iz >= 75:
        return "confortável"
    if iz >= 50:
        return "bom"
    return "limitado"


def carrega(path: str):
    rows = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            rows.append({
                "entry": r["entry"].strip(),
                "ctx": int(r["ctx"]),
                "decode": float(r["decode_tps"]),
                "prefill": float(r["prefill_tps"]),
            })
    return rows


def main():
    ap = argparse.ArgumentParser(description="IZ — Índice Zoo")
    ap.add_argument("--file", default=DEFAULT_CSV, help=f"CSV de dados (default: {DEFAULT_CSV})")
    ap.add_argument("--markdown", action="store_true", help="saída em markdown")
    args = ap.parse_args()

    if not os.path.exists(args.file):
        sys.exit(f"arquivo de dados não encontrado: {args.file}")
    rows = carrega(args.file)

    for r in rows:
        t = r["ctx"] / r["prefill"]
        d, p = d_norm(r["decode"]), p_norm(t)
        r["t"] = t
        r["d"], r["p"] = d, p
        r["iz"] = 100.0 * min(d, p)
        r["lim"] = limitador(d, p)
        r["lei"] = leitura(r["iz"], r["decode"], t)

    rows.sort(key=lambda r: -r["iz"])

    if args.markdown:
        print("| # | Entry | Decode | t p/ ler a janela | **IZ** | O que limita |")
        print("|---|---|---|---|---|---|")
        for i, r in enumerate(rows, 1):
            print(f"| {i} | {r['entry']} | {r['decode']:.0f} t/s | "
                  f"{r['t']:.1f} s ({r['ctx']//1024}k) | **{r['iz']:.1f}** | "
                  f"{r['lei'] if r['lei'] == 'não usável' else r['lim']} |")
        return

    hdr = f"{'#':>3} {'Entry':<34} {'decode':>8} {'t janela':>10} {'D':>5} {'P':>5} {'IZ':>6}  leitura"
    print(hdr)
    print("-" * len(hdr))
    for i, r in enumerate(rows, 1):
        print(f"{i:>3} {r['entry']:<34} {r['decode']:>6.0f} t/s {r['t']:>8.1f} s "
              f"{r['d']:>5.2f} {r['p']:>5.2f} {r['iz']:>6.1f}  {r['lei']}")
    print(f"\nfonte: {os.path.relpath(args.file, os.path.dirname(HERE))} | "
          f"IZ = 100·min(D,P) — âncoras: decode 25/50/100 t/s, ingestão 320/128/32 s")


if __name__ == "__main__":
    main()
