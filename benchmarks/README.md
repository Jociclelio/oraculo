# benchmarks/ — curvas de desempenho do zoológico

Medição padronizada por modelo, gerando 4 gráficos:

1. **Decode × contexto** — decode (t/s) com o contexto cheio de 0→128k
2. **Superfície 3D prefill** — batch × ubatch → prefill (t/s) por modelo
3. **Prefill × contexto** — prefill (t/s) de 0→128k (confirma constância)
4. **Tempo para processar** — tempo acumulado do prefill até X tokens

## Receita comum a todos os modelos

- **KV quant único**: `-ctk q5_1 -ctv q5_1` (regra 10 — K/V misto destrói os
  híbridos GDN/SWA no stock; tipo único é obrigatório)
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

## Limitações conhecidas

- **`-d` (n_depth) do llama-bench** é patológico nesta build (churn de CUDA
  graphs) — não usamos; o contexto cheio vem do prompt real.
- **llama-bench decode** nos híbridos GDN é ~6× subestimado — usar o sweep
  e2e para decode.
- Prompts sintéticos (palavras) têm entropia maior que texto real; o
  prefill de texto real tende a ser ligeiramente mais rápido (menos bits
  por token após compressão do tokenizer).
- Entradas que compartilham GGUF + ncmoe (General/It_*) são medidas uma vez.
