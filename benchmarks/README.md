# benchmarks/ — curvas de desempenho do zoológico

Medição padronizada por modelo, gerando 4 gráficos:

1. **Decode × contexto** — decode (t/s) com o contexto cheio de 0→128k
2. **Superfície 3D prefill** — batch × ubatch → prefill (t/s) por modelo
3. **Prefill × contexto** — prefill (t/s) de 0→128k (confirma constância)
4. **Tempo para processar** — tempo acumulado do prefill até X tokens

## Receita comum a todos os modelos

- **KV quant único**: o vigente no `config.yaml` (regra 10 — desde
  2026-10-27, `-ctk q4_0 -ctv q4_0`; tipo único K=V obrigatório)
- **Visão plena**: `--mmproj` carregado nos modelos que suportam
- **Corte de VRAM ~10 GB**: `-ncmoe` de serving por modelo (validado por
  carga real; o processo pode passar um pouco)
- `-fa on -t 5 -c 131072 -ngl 99`, receita idêntica ao serving

## Uso

```bash
cd /home/jocic/oraculo

./benchmarks/bench.sh all              # sweep e2e + pp3d (~2-3 h)
./benchmarks/bench.sh all sweep        # só o sweep e2e (gráficos 1/3/4)
./benchmarks/bench.sh all pp3d         # só a superfície batch×ubatch
DRY=1 ./benchmarks/bench.sh all        # só imprime comandos

python3 benchmarks/aggregate.py        # consolida results/e2e.csv + pp3d.csv
python3 benchmarks/plot.py             # PNGs em results/plots/
```

Resultados brutos: `results/<entry>__e2e.csv` (1 linha por ponto de contexto:
prompt_n, prefill_tps, decode_tps, tempos) e `results/<entry>__pp3d.csv`
(saída crua do llama-bench; 1 linha por batch×ubatch). VRAM de pico do sweep
fica em `results/.vram_<entry>`.

## Séries

### `sweep` — llama-server e2e (gráficos 1, 3 e 4)

Sobe o servidor com a **receita de serving** (mesmos flags do config,
incl. mmproj e MTP) e dispara requests de contexto crescente
(≈0, 16k, 32k, 64k, 96k, 127k tokens). Cada request mede:

- `prefill_tps` — tokens/s do prefill do prompt (gráfico 3)
- `decode_tps` — tokens/s gerando com o contexto cheio (gráfico 1)
- `prefill_s` — tempo total para processar o prompt (gráfico 4)

Prompts são palavras sorteadas com seed por tamanho (sem prefixo comum, para
não acionar o cache-reuse entre pontos). O decode inclui o efeito do
speculative decoding (MTP) quando o modelo tem — é o desempenho real de
serving. Por isso o e2e substitui o llama-bench para decode: o llama-bench
desta build (11561) mede decode ~6× abaixo do serving nos híbridos GDN
(bug upstream, GPU 2% / CPU ~500% durante o tg).

### `pp3d` — llama-bench (gráfico 2)

`-p 8192 -n 0` com `batch ∈ {512,1024,2048,4096}` × `ubatch ∈
{256,512,1024,2048}` (ub ≤ batch), 2 repetições. Prefill no llama-bench é
confiável (validado contra o serving); decode não (ver acima).

### `sweep_ctx.py` — sweep de contexto via llama-swap (gráficos 1/3/4 "reais")

Varre o contexto 0→130k em passos de ~8k batendo no **serving** (`:8081`,
receita do `config.yaml` — inclui MTP/draft, pdcache e KV vigentes). É a
medição que alimenta o gráfico decode+prefill+IZ × contexto e o ranking do
Índice Zoo. Saída: `results/ctxsweep/<entry>__ctxsweep.json` +
consolidado `results/ctxsweep__<data>.csv`.

```bash
python3 benchmarks/sweep_ctx.py <entry> [entry2 ...]
python3 benchmarks/plot_ctx.py <entry>        # PNG em results/plots/ctxsweep/
python3 benchmarks/plot_ctx.py --all
```

O gráfico tem 3 curvas: **decode (t/s)** na régua do eixo esquerdo,
**prefill (t/s)** na régua do eixo direito e **IZ** num eixo no MEIO do
gráfico (0–100) com linhas de referência em iz = 25/50/75/100.

Diferenças para o `bench.sh sweep`: usa texto real pt-BR crescente
(pdcache entre pontos — conferir `cache_n`) em vez de prompts sintéticos
independentes, e mede o desempenho de serving real (draft MTP incluso).

## Calibração de batch/ubatch — `calibrate.sh`

Varre a grade `batch × ubatch` medindo **prefill e2e** (llama-server na
receita de serving da entry, prompt real ~8k tokens, `n_predict=1`) e elege
o ótimo dentro do teto de VRAM. Complementa o `pp3d` (medição e2e real,
poda por VRAM, sugere/aplica o resultado no `config.yaml`).

```bash
./benchmarks/calibrate.sh <entry>              # varre a grade e reporta
./benchmarks/calibrate.sh <entry> --apply      # aplica o vencedor no config
DRY=1 ./benchmarks/calibrate.sh <entry>        # só imprime comandos

# grade default: b ∈ {1024,2048,4096,8192} × ub ∈ {512,1024,2048,4096}
CAL_B="2048 4096 8192" CAL_UB="1024 2048 4096" ./benchmarks/calibrate.sh <entry>
```

**Regras de método** (as mesmas descobertas de 2026-10-26):

- **Medir com a receita COMPLETA de serving** — o draft MTP consome compute
  buffer: sem ele, `ub 4096` carrega no Qwen3.6 35B (1585 tok/s); com ele,
  a carga aborta (FAIL). Passar os flags do draft em `CAL_EXTRA_FLAGS`.
- **VRAM de pico** amostrada a cada 2 s; acima de `CAL_VRAM_CEIL` (default
  11700 MiB) o combo é marcado `OVER` e nunca eleito.
- Reps com **prompts de seeds diferentes** — prompt repetido aciona o prompt
  cache de RAM e falseia a 2ª medição.
- Cada combo é um container novo; modelo que falha a carga = `FAIL` (não é
  elegível), request que falha = `FAIL` também (flake não vira "0 tok/s OK").
- Resultado: `results/<entry>__calib.csv`; ~40-70 s por combo.

**Leis de comportamento medidas (RTX 3060 12 GB, gpu-unlock ativo):**

- O **ubatch domina** o prefill de MoE (amortiza a re-leitura de pesos de
  experts da RAM — regra 7); o batch é irrelevante acima de ~4096 (b4096 vs
  b8192 no mesmo ub = ruído).
- Valores absolutos dependem do **boot** (gpu-unlock BF16 ~+50% vs stock) e
  da build do llama.cpp — comparar apenas medições do mesmo boot/build.
- Sem draft MTP, `ub 4096` cabe e é o vencedor; com draft, `ub 2048` é o
  teto (ub4096 aborta a carga).

## Probe de profundidade — `probe_depth.py`

Tuning de variantes de configuração sem sweep completo: replica a receita de
serving da entry e injeta os flags da variante por cima (último valor vence),
medindo só **3 pontos (8k/64k/130k)** por variante (~3-4 min cada): decode,
prefill, aceitação do draft e VRAM de pico. Compara a **razão de planura**
`dec@130k / dec@8k`. O vencedor vai para o `config.yaml` após validação de
carga (o probe já é a carga) e sweep completo.

```bash
python3 benchmarks/probe_depth.py                          # bateria default
PROBE_VARIANTS="base combo" python3 benchmarks/probe_depth.py
DRY=1 python3 benchmarks/probe_depth.py                    # só imprime comandos
```

Resultado da bateria de 2026-10-28 (Qwen3.6_35B_A3B, dec t/s @8k/64k/130k):

| variante | @8k | @64k | @130k | planura | acc@130k |
|---|---|---|---|---|---|
| base (n-max 2) | 45,1 | 38,9 | 29,7 | 0,66 | 0,85 |
| n1 | 41,1 | 33,7 | 27,9 | 0,68 | 0,93 |
| n3 | 46,9 | 40,9 | 31,9 | 0,68 | 0,77 |
| pmin50 | 44,3 | 39,8 | 31,7 | 0,72 | 0,89 |
| pmin70 | 45,2 | 40,3 | 29,3 | 0,65 | 0,92 |
| **pmin50n3** | 42,5 | 41,1 | 33,0 | **0,78** | 0,86 |
| ncmoe32 | 46,9 | 38,9 | 31,8 | 0,68 | 0,85 |
| ngram (draft-mtp,ngram-simple) | 42,4 | 36,7 | 25,8 | 0,61 | 0,60 |
| **combo (n3+pmin0.5+ncmoe32)** | **47,1** | 40,7 | **33,5** | 0,71 | 0,86 |

**Vencedor: `combo`** — domina absolutamente (melhor em todos os pontos;
a planura menor do que pmin50n3 é só o raso mais rápido). `--spec-draft-p-min
0.5` filtra drafts fracos na cauda (acc@130k 0,85→0,86 com n-max 3, e
-13% de drafts desperdiçados); `n-max 3` rende no meio da janela;
`-ncmoe 32` levanta o raso (experts: mais 1 camada na GPU). O ngram
empilhado ao MTP foi RUIM (acc desaba para 0,60 — rejeitado).

## Limitações conhecidas

- **`-d` (n_depth) do llama-bench** é patológico nesta build (churn de CUDA
  graphs) — não usamos; o contexto cheio vem do prompt real.
- **llama-bench decode** nos híbridos GDN é ~6× subestimado — usar o sweep
  e2e para decode.
- Prompts sintéticos (palavras) têm entropia maior que texto real; o
  prefill de texto real tende a ser ligeiramente mais rápido (menos bits
  por token após compressão do tokenizer).
- Entradas que compartilham GGUF + ncmoe (General/It_*) são medidas uma vez.
