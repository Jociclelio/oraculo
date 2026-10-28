# Instalação de Modelos LLM

Este guia explica como instalar modelos GGUF no servidor oráculo e expô-los
pelo **llama-swap** (proxy em `127.0.0.1:8081` que sobe um container
efêmero por modelo). Os parâmetros de cada modelo vivem em
[`../llama-swap/config.yaml`](../llama-swap/config.yaml) — o antigo
`models.ini` está **desativado/histórico** (mantido no repo só como
referência do serviço `llama-cpp` removido).

---

## Estrutura

```
models/
├── models.ini                # HISTÓRICO (desativado) — parâmetros migraram p/ llama-swap/config.yaml
├── MODELS_INSTALL.md         # Este arquivo
├── MiniCPM-V-4.7-1B-Q4_K_M/
│   ├── MiniCPM-V-4_7-1B-Q4_K_M.gguf
│   └── mmproj-model-f16.gguf
├── Ornith-1.5-9B-Q4_K_M/
│   ├── Ornith-1.5-9B-Q4_K_M.gguf
│   └── mmproj-Ornith-1.5-9B-BF16.gguf
├── Qwen3.5-9B-Uncensored-HauhauCS/
│   ├── Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf
│   └── mmproj-Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-BF16.gguf
├── LFM2.5-24B-A2B-GGUF/
│   └── LFM2.5-24B-A2B-Q4_K_M.gguf
├── LFM2.5-24B-A2B-IQ2_M/                # unsloth UD (variante 100% GPU)
│   └── LFM2.5-24B-A2B-UD-IQ2_M.gguf
├── Ornith-1.5-35B-A3B-Q4_K_M/
│   └── Ornith-1.5-35B-A3B-Q4_K_M.gguf
├── Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced/
│   └── modelo.gguf
├── Ternary-Bonsai-2-27B-gguf/          # Bonsai 2 (ver seção própria abaixo)
│   ├── Ternary-Bonsai-2-27B-PTQ1_0.gguf
│   └── Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf
├── Ternary-Bonsai-2-9B-gguf/           # Bonsai 2 9B (engine PrismML)
│   ├── Ternary-Bonsai-2-9B-PTQ1_0.gguf
│   └── Ternary-Bonsai-2-9B-mmproj-Q8_0.gguf
├── Ternary-Bonsai-2-9B-Uncensored-LoRA/ # adapter AtomicChat (3,2 MB, rank-1)
│   └── Ternary-Bonsai-2-9B-Uncensored-LoRA.gguf
├── MiMo-V2.6-Distill-Qwen-9B-GGUF/     # Xiaomi MiMo (arch qwen35 denso)
│   ├── MiMo-V2.6-Distill-Qwen-9B-Q4_K_M.gguf
│   └── mmproj-MiMo-V2.6-Distill-Qwen-9B-f16.gguf
├── Ternary-Bonsai-2-27B-Heretic/       # finetune uncensored (engine PrismML)
│   ├── Ternary-Bonsai-2-27B-Uncensored-Heretic-PTQ1_0.gguf
│   └── mmproj-Q8_0.gguf
├── Xing4.0-29B-A4B-Q4_K_M/             # Xing4.0 (ver seção própria abaixo)
│   └── Xing4.0-29B-A4B-Q4_K_M.gguf
├── comfyui/                            # Difusão (ver seção "Modelos de Difusão")
│   ├── diffusion_models/
│   ├── text_encoders/
│   └── vae/
└── ...
```

Cada modelo tem sua própria subpasta contendo o arquivo `.gguf` e arquivos auxiliares (mmproj, mtp, etc.). O monte `./models:/models` é compartilhado por todos os containers de modelo do llama-swap.

---

## Pré-requisitos

- **10-100 GB** de disco livre por modelo (dependendo do tamanho e quantização)
- Acesso à internet para download dos modelos
- Para downloads do Hugging Face: `huggingface_hub` (`hf download`) ou `wget`/`curl`

---

## Passo a Passo

### 1. Escolher o Modelo

Consulte a tabela de entries em [`AGENTS.md`](../AGENTS.md#modelos-llama-swapconfigyaml)
e o próprio [`llama-swap/config.yaml`](../llama-swap/config.yaml).

### 2. Criar a Pasta do Modelo

```bash
mkdir -p models/NOME_DO_MODELO/
```

### 3. Baixar o Modelo GGUF

Use `wget` ou `curl` para baixar o arquivo do repositório Hugging Face:

```bash
cd models/NOME_DO_MODELO/
wget https://huggingface.co/usuario/modelo/resolve/main/modelo.gguf
```

Ou, com o CLI do Hugging Face (recomendado; retoma downloads):

```bash
hf download usuario/modelo arquivo.gguf --local-dir models/NOME_DO_MODELO
```

> **Dica:** Modelos quantizados (Q4_K_M, Q5_K_M) oferecem bom equilíbrio entre qualidade e tamanho.

### 4. Criar a Entry no llama-swap/config.yaml

Adicione uma entry em [`llama-swap/config.yaml`](../llama-swap/config.yaml)
usando uma das macros — `docker-stock` (llama.cpp oficial),
`docker-prismml` (fork PrismML, obrigatório para Bonsai) ou `docker-xing`
(fork shuxiaoqiong, obrigatório para Xing4.0).

**Convenção de contexto no nome da entry** (validar VRAM por carga real):
entry sem sufixo = 128k (floor, `-c 131072`; o KV quantizado
`-ctk q5_1 -ctv q5_1` dos macros é o que viabiliza isso). Modelo que não
alcança 128k é **removido** (política 2026-10-26 — precedente:
K2-Horizon 40k).

```yaml
  NOME_DO_MODELO:
    cmd: |
      ${docker-stock}
      -m /models/NOME_DO_MODELO/modelo.gguf
      -c 49152 -ngl 99
    cmdStop: ${docker-stop}
    ttl: 300
```

### 5. Reiniciar o proxy e testar

```bash
./manage.sh restart                       # recarrega o config.yaml
curl http://localhost:8081/v1/models      # a entry deve aparecer
```

Não há `load_model`: o modelo carrega automaticamente no primeiro request à
entry (e descarrega após `ttl: 300` s ocioso).

---

## Bonsai 2 27B (GGUFs ternários — engine PrismML)

Os GGUFs do **Bonsai 2 27B** (PrismML) vivem em
`models/Ternary-Bonsai-2-27B-gguf/`. Origem: `prism-ml/Ternary-Bonsai-2-27B-gguf`
no Hugging Face:

```bash
hf download prism-ml/Ternary-Bonsai-2-27B-gguf \
  Ternary-Bonsai-2-27B-PTQ1_0.gguf \
  Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf \
  --local-dir models/Ternary-Bonsai-2-27B-gguf
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `Ternary-Bonsai-2-27B-PTQ1_0.gguf` | ~5,6 GB | entry `bonsai-27b` (+ mmproj, visão) |
| `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf` | ~601 MB | visão (mmproj) |

> A variante `PQ2_0` (~6,8 GB, entry `bonsai-27b-pq2_0`) foi removida em
> 2026-10-13 — manteve-se só o PTQ1_0, a quantização menor.

### Bonsai 2 27B "ada" (runtime alternativo — engine ada-ternary, entry `bonsai-27b-ada`)

Instalado em 2026-10-26: MESMOS pesos ternários PTQ1_0, mas servidos pelo
fork `llama.cpp-ada-ternary` (branch `bonsai-q8-product`, commit pinado
`2cadbfb6` = PrismML `adfffbe` + a pilha de 71 patches do projeto
[professorpalmer/bonsai-ada-surgery](https://github.com/professorpalmer/bonsai-ada-surgery)).
O GGUF é o oficial do projeto, com a head MTP da ProCreations enxertada
(`blk.64`; os 851 tensors do trunk são byte-idênticos ao PTQ1_0 do PrismML):

```bash
hf download CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF \
  Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf \
  --local-dir models/Ternary-Bonsai-2-27B-262k-GGUF
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf` | ~6,4 GB | entry `bonsai-27b-ada` (mmproj reutilizado do dir `Ternary-Bonsai-2-27B-gguf/`) |

A engine é construída com `./engines/llama.cpp-bonsai-ada/build.sh`. A
entry usa a receita 12 GB do launcher do projeto: KV q4_0 TIERED
(`--kv-vram-cells` — posições em VRAM, resto em RAM pinneada,
bit-idêntico), MTP self-draft (`--spec-type ngram-mod,draft-mtp`,
`draft-n-max 2` / `tail 4`, draft window 16k) + lookup drafting (n-gram,
32), mmproj na CPU (`--no-mmproj-offload`) e harness-proofing de
reasoning (`--reasoning-effort-allow medium`, budget 20480 com
fechamento forçado). Medições e2e na RTX 3060 (2026-10-26): **decode
~52 tok/s @5,5k, ~49 @45k, ~38 @130k, ~32 @175k** vs stock prism 23/16
nos mesmos prompts; prefill igual ao stock; aceitação do draft ~69-91%.
SEM pdcache/sleep (o patch de disco é contra o master ggml-org).

#### Bonsai 2 27B "ada" Uncensored (LoRA AtomicChat — entry `bonsai-27b-ada-uncensored`)

Adicionada em 2026-10-28: a MESMA entry `bonsai-27b-ada` + LoRA rank-1 de
9,7 MB do AtomicChat que remove a direção de recusa no grafo (base
byte-idêntico, nada re-quantizado; método Arditi et al. 2024). A LoRA foi
construída sobre o PTQ1_0 do PrismML — cujo trunk é byte-idêntico ao GGUF
262k acima — e os 129 sites-alvo (64 `ffn_down` + 48 `ssm_out` + 16
`attn_output` + `token_embd`) foram verificados presentes no GGUF c/ MTP
(metadata `prism.abliterate.*` embarcado, direction_row 42).

```bash
hf download AtomicChat/Ternary-Bonsai-2-27B-Uncensored-LoRA-GGUF \
  bonsai2-27b-uncensored-own42-lora.gguf \
  --local-dir models/Ternary-Bonsai-2-27B-Uncensored-LoRA
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `bonsai2-27b-uncensored-own42-lora.gguf` | 9,7 MB | `--lora-scaled :1.5` na entry `bonsai-27b-ada-uncensored` |

**Scale 1,5** é o ponto validado pelo autor: refusals 99%→0% (em 1,0
ainda 14% recusam; em 2,0 replies vazios) com MMLU 73.2→73.0. Outros
arquivos no mesmo repo: `own38` (segunda direção) e
`own42-layers15-63` (sem embedding — pior segundo o autor). **NÃO
VALIDADO em carga nesta máquina** (GPU ocupada na adição) — validar
recusas, tok/s e aceitação do draft-mtp com a LoRA ativa ao ativar.

### Bonsai 2 9B (variante edge — engine PrismML, entry `bonsai-9b`)

Instalado em 2026-10-20 (origem `prism-ml/Ternary-Bonsai-2-9B-gguf`):

```bash
hf download prism-ml/Ternary-Bonsai-2-9B-gguf \
  Ternary-Bonsai-2-9B-PTQ1_0.gguf \
  Ternary-Bonsai-2-9B-mmproj-Q8_0.gguf \
  --local-dir models/Ternary-Bonsai-2-9B-gguf
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `Ternary-Bonsai-2-9B-PTQ1_0.gguf` | ~2,0 GB | entry `bonsai-9b` (+ mmproj, visão) |
| `Ternary-Bonsai-2-9B-mmproj-Q8_0.gguf` | ~0,6 GB | visão (mmproj) |

Mesma engine PrismML pinada do irmão 27B. **KV bf16 @192k (2026-10-20)**:
no fork, o KV q5_1 dos macros NÃO tem caminho rápido de flash attention
(issue PrismML #191) — degrada com o contexto (medido: decode 12,6 vs
~71-78 tok/s @4k com f16/bf16; prefill 41 vs ~1600-1723). O ctx nativo
256k NÃO cabe na RTX 3060 (OOM na carga); 224k carrega sem margem; o
teto seguro é **192k** (VRAM ~10,6 GB). Com bf16 @192k: **decode ~71
tok/s @4k (~48 @21k), prefill ~1600 tok/s**. Visão validada.
O repo HF publica também drafts `DFlash2-Q8_0` (1,6 GB) e
`PQ2_0-MTP-Q8_0` (2,7 GB) — não baixados.

### Bonsai 2 9B Uncensored (AtomicChat — LoRA, entry `bonsai-9b-uncensored`)

Adapter LoRA **rank-1 de 3,2 MB** (não é checkpoint) que remove a direção
de recusa no grafo de computo, com o pack base PTQ1_0 byte-idêntico —
nada é re-quantizado. Origem: `AtomicChat/Ternary-Bonsai-2-9B-Uncensored-LoRA-GGUF`
(recusas 100% → 0% em scale 1; custo ~4,3 pontos de MMLU; leak residual
~1e-4). O entry reutiliza os MESMOS GGUFs do `bonsai-9b` + `--lora-scaled`:

```bash
hf download AtomicChat/Ternary-Bonsai-2-9B-Uncensored-LoRA-GGUF \
  Ternary-Bonsai-2-9B-Uncensored-LoRA.gguf \
  --local-dir models/Ternary-Bonsai-2-9B-Uncensored-LoRA
```

> Requer o fork PrismML (stock nem abre o pack ternário). LoRA medido pelo
> autor no fork `prism-b10777`; aqui validado no pin `84445367f`
> (aplicação confirmada por logprobs distintos vs base — 2026-10-20).
> MESMO KV f16 do `bonsai-9b`. Atenção: o modelo é thinking e consome
> muitos tokens de raciocínio (~900 para uma pergunta simples) — orçar
> `max_tokens` generoso ou a resposta vem vazia.

> ⚠️ **Regra dura — nunca engine stock**: GGUFs ternários PTQ1_0/PQ2_0 só
> funcionam no fork **PrismML-Eng/llama.cpp** (kernels ternários + Hadamard).
> A imagem stock recusa esses quantizados ou carrega como `Q2_0` legacy
> gerando lixo. A entry `bonsai-27b` usa a imagem
> local `llama.cpp-prismml:latest` (build em `engines/llama.cpp-prismml/`,
> fork pinado no commit `84445367f`). Se a imagem não existir, construa:
> `./engines/llama.cpp-prismml/build.sh`.

> **MTP do Bonsai não foi baixado** (arquivo draft MTP ~7 GB no repo
> upstream; fora de escopo do plano llama-swap-multi-engine). As entries
> atuais não usam `--model-draft`. NOTA 2026-10-26: o MTP chegou por outro
> caminho — a entry `bonsai-27b-ada` usa o GGUF com a head enxertada
> (`draft-mtp` self-draft, sem `--model-draft`); a entrada acima refere-se
> aos drafts DFlash do repo prism-ml, que continuam não baixados.

Nesta máquina os arquivos foram **migrados** de `/home/jocic/bonsai-llm/models/`
(task 004 do plano) — o comando `hf download` acima é o caminho para
instalação nova.

---

## Xing4.0 29B-A4B (engine dedicada — fork shuxiaoqiong)

GGUF Q4_K_M do **Xing4.0-29B-A4B** (China Telecom AI, sucessor do TeleChat —
MoE 29B/4B ativo, MLA + mHC hyper-connections + MTP head, contexto nativo
256K). Origem: `Venastine-Research/Xing4.0-29B-A4B-GGUF`:

```bash
hf download Venastine-Research/Xing4.0-29B-A4B-GGUF \
  Xing4.0-29B-A4B-Q4_K_M.gguf \
  --local-dir models/Xing4.0-29B-A4B-Q4_K_M
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `Xing4.0-29B-A4B-Q4_K_M.gguf` | ~19 GB | entry `Xing4.0_29B_A4B` |

> ⚠️ **Regra dura — nunca engine stock**: a arquitetura `xing4_0` **não está
> no llama.cpp upstream** (PR ggml-org#29012, aberto/não mergeado). A imagem
> stock recusa o GGUF. As entries usam a imagem local
> `llama.cpp-xing:latest` — build em `engines/llama.cpp-xing/` a partir do
> fork `shuxiaoqiong/llama.cpp` (branch `xing4_0-port`), pinado no commit
> `8c379195a` (HEAD do PR). Se a imagem não existir, construa:
> `./engines/llama.cpp-xing/build.sh`. Fingerprint em runtime:
> `system_fingerprint: "b1-8c37919"`.

> ⚠️ **`--load-mode none` é obrigatório** nesta entry: com mmap + overrides
> de tensor para CPU (`-ncmoe`), o desempenho desaba (medido: 1,2 tok/s);
> sem mmap: ~12,5 tok/s (RTX 3060 12GB, ncmoe 24, ctx 49152, VRAM
> 10570/12288 MiB).

> **MTP draft**: o repo só publica arquivos `-MTP` nas quantizações IQ3
> (não há Q4_K_M-MTP) — a entry não usa speculative decoding; os tensors
> `nextn` embutidos no GGUF são ignorados pelo loader.

---

## Strata (Qwen3.8-Flash-Next) — não baixado

O modelo **Strata não foi baixado** (~58 GB na variante Coder IQ1_M; decisão
de escopo do plano). A infraestrutura está pronta em
[`../engines/strata/`](../engines/strata/) (Dockerfile pinado + `README.md` com os passos de
instalação futura) e a entry `Strata:` permanece **comentada** no
`llama-swap/config.yaml`. Para ativar: seguir `engines/strata/README.md` e
descomentar a entry.

---

## Parâmetros Comuns

Os parâmetros de cada entry vivem comentados no
[`llama-swap/config.yaml`](../llama-swap/config.yaml). Flags do
`llama-server` usadas nas entries (coluna direita = antigo parâmetro do
`models.ini`, hoje só histórico):

| Flag | Descrição | Valores típicos | (models.ini) |
|------|-----------|-----------------|--------------|
| `-m` | Caminho ao `.gguf` (dentro do container) | `/models/NOME/modelo.gguf` | `model` |
| `-c` | Tamanho do contexto | `49152`, `65536` | `ctx-size` |
| `-ngl 99` | Camadas na GPU (todas) | `99` | `ngl = all` |
| `--temp` | Temperatura | `0.6` (código), `1.0` (geral) | `temp` |
| `--top-p` | Amostragem top-p | `0.9`, `0.95` | `top-p` |
| `--top-k` | Amostragem top-k | `16`, `32`, `64` | `top-k` |
| `--mmproj` | Arquivo multimodal | `/models/NOME/mmproj-*.gguf` | `mmproj` |
| `--model-draft` | Modelo draft (MTP/DFlash) | `/models/NOME/draft.gguf` | `model-draft` |
| `-ncmoe` | Experts MoE na CPU | `24`, `28`, `32` | `n-cpu-moe` |
| `-b` / `-ub` | Batch / micro-batch | `4096` / `256-512` | `batch-size`/`ubatch-size` |

Flags globais (flash-attn, jinja, `-np 1`, KV q8_0, cache-reuse/ram,
threads) já vêm nas macros `docker-stock`/`docker-prismml`/`docker-xing`.

---

## Modelos Multimodais

Modelos com capacidade visual (imagem) requerem um arquivo `mmproj` na entry:

```yaml
  NOME_MULTIMODAL:
    cmd: |
      ${docker-stock}
      -m /models/NOME/modelo.gguf
      --mmproj /models/NOME/mmproj-model-f16.gguf
      -c 49152 -ngl 99
    cmdStop: ${docker-stop}
    ttl: 300
```

Baixe o arquivo mmproj do mesmo repositório Hugging Face do modelo.

---

## Modelos MoE (Mixture of Experts)

Modelos MoE (ex: Qwen 35B-A3B) usam `-ncmoe` para distribuir experts na CPU:

```yaml
      -m /models/NOME/modelo.gguf
      --load-mode none
      -c 49152 -ngl 99 -ncmoe 28
```

> ⚠️ **`--load-mode none` é praticamente obrigatório em entries MoE com
> `-ncmoe`**: com mmap + overrides de tensor para CPU, o desempenho desaba
> silenciosamente (medido: Qwen3.6 35B MTP de 1,3 → 27-33 tok/s; Xing4.0 de
> 1,2 → 12,5 tok/s). O loader avisa no log do container:
> `tensor overrides to CPU are used with mmap enabled`.

---

## MiniCPM-V 4.7 35B-A3B (OpenBMB — multimodal MoE)

Primeiro MoE multimodal da série MiniCPM-V. Backbone Qwen3.6-35B-A3B
(arch `qwen35moe`: 41 camadas, 256 experts, 8 ativos, Gated DeltaNet +
full attention a cada 4; ctx nativo 262144) + visor SigLIP2 (LLaVA-UHD v4).
GGUF oficial: `openbmb/MiniCPM-V-4.7-35B-A3B-gguf`.

```bash
hf download openbmb/MiniCPM-V-4.7-35B-A3B-gguf \
  MiniCPM-V-4_7-35B-A3B-Q4_K_M.gguf \
  mmproj-model-f16.gguf \
  --local-dir models/MiniCPM-V-4.7-35B-A3B-Q4_K_M
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `MiniCPM-V-4_7-35B-A3B-Q4_K_M.gguf` | ~21,2 GB | entry `MiniCPM-V_4.7_35B` |
| `mmproj-model-f16.gguf` | ~1,1 GB | visão (mmproj) |

> ⚠️ **Requer llama.cpp ≥ PR ggml-org#29416** (merge 2026-10-10): suporte ao
> visor `minicpmv4_7` + `rope.section_order zyxt`. A imagem stock local foi
> atualizada para o build 11561 (`0.6.0-dev`, fingerprint `b11561-e937b17a2`)
> — a anterior (build 11312, 01/10) não carregava o mmproj.

> **SEM MTP**: o GGUF declara `nextn_predict_layers=1` mas não contém tensors
> `nextn` (verificado no header; o safetensors de 70 GB também não tem —
> a speculação oficial da série é draft **DSpark**, não MTP).

### Draft DSpark (testado e DESCARTADO)

O draft oficial (`openbmb/MiniCPM-V-4.7-35B-A3B-DSpark`, safetensors 778 MB)
foi convertido para GGUF e testado em 2026-10-12:

```bash
# conversão (precisa de venv com transformers + sentencepiece):
python3 -m venv --system-site-packages /tmp/conv-venv
/tmp/conv-venv/bin/pip install transformers sentencepiece
# tokenizer/config do target num subdiretório (--target-model-dir exige dir local):
hf download openbmb/MiniCPM-V-4.7-35B-A3B tokenizer.json tokenizer_config.json \
  chat_template.jinja config.json --local-dir models/MiniCPM-V-4.7-35B-A3B-DSpark/target
/tmp/conv-venv/bin/python convert_hf_to_gguf.py \
  models/MiniCPM-V-4.7-35B-A3B-DSpark --outtype q8_0 \
  --target-model-dir models/MiniCPM-V-4.7-35B-A3B-DSpark/target
```

Resultado: aceitação ~10% e decode 9,5 tok/s (vs 32-35 sem draft); o compute
buffer do draft (~3,9 GB — logits de vocab 248k × ubatch) também não cabe na
VRAM junto do target (`-devd none`/`-ngld 0` abortam no scheduler). O GGUF
do draft (413 MB) foi **apagado em 2026-10-26** (limpeza de disco) — para
reteste, refazer a conversão acima. A entry serve **sem** speculative
decoding.

---

## MiniCPM-V 4.7 1B (OpenBMB — multimodal denso)

Variante edge da série MiniCPM-V 4.7: **denso** (arch `qwen35`, sem experts
— sem `-ncmoe`/`--load-mode none`), mesmo visor LLaVA-UHD v4 da 35B, ctx
nativo 262144. Origem: `openbmb/MiniCPM-V-4.7-1B-gguf`:

```bash
hf download openbmb/MiniCPM-V-4.7-1B-gguf \
  MiniCPM-V-4_7-1B-Q4_K_M.gguf \
  mmproj-model-f16.gguf \
  --local-dir models/MiniCPM-V-4.7-1B-Q4_K_M
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `MiniCPM-V-4_7-1B-Q4_K_M.gguf` | ~0,9 GB | entry `MiniCPM-V_4.7_1B` |
| `mmproj-model-f16.gguf` | ~0,8 GB | visão (mmproj; existe variante `-4x` com compressão mista 4x/16x de tokens visuais, não instalada) |

> **SEM MTP na entry**: o repo publica o draft DSpark
> (`dspark-MiniCPM-V-4_7-1B-F16.gguf`) mas não o instalamos — precedente da
> 35B: aceitação ~10% (mais lento que sem draft).

> Medido (2026-10-16, RTX 3060 12 GB, display idle; bench prefill/decode):
> **decode ~200 tok/s, prefill ~8000-8500 tok/s** (4k-16k); visão validada;
> modelo reasoning (`reasoning_content` separado). VRAM total com o Ornith
> 9B na sequência de testes: ambos < 10 GB.

---

## Ornith-1.5-9B (ornith-ai — denso, raciocínio agêntico)

Variante edge da família Ornith-1.5 (a 35B-A3B é MoE; a 9B é **densa**,
arch `qwen35`, sem `-ncmoe`/`--load-mode none`). Raciocínio com
`<think/tool_call>` (template Qwen3), ctx nativo 262144, head MTP embutida
(`nextn=1`, validado no header) → `--spec-type draft-mtp` self-draft (regra
5, sem `--model-draft`). Origem: `ornith-ai/Ornith-1.5-9B-GGUF`:

```bash
hf download ornith-ai/Ornith-1.5-9B-GGUF \
  Ornith-1.5-9B-Q4_K_M.gguf \
  mmproj-Ornith-1.5-9B-BF16.gguf \
  --local-dir models/Ornith-1.5-9B-Q4_K_M
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `Ornith-1.5-9B-Q4_K_M.gguf` | ~5,5 GB | entry `Ornith1.5_9B` |
| `mmproj-Ornith-1.5-9B-BF16.gguf` | ~0,8 GB | visão (mmproj) |

> Sampling do model card — **general**: temp 1.0 / top-p 0.95 / top-k 20 /
> min-p 0.0 / presence-penalty 1.5 / rep 1.0; **coding**: temp 0.6 /
> presence 0.0. Medido (2026-10-16, bench prefill/decode): **decode
> ~48-52 tok/s, prefill ~1430-1580 tok/s** (4k-16k), aceitação draft
> ~0,53-0,69, VRAM 9862 MiB @ 128k.

---

## Modelos com MTP (Multi-Token Prediction)

Para acelerar a geração, use um drafter na entry (ex.: `Gemma4_12B_MTP`):

```yaml
      -m /models/NOME/modelo.gguf
      --model-draft /models/NOME/modelo-draft.gguf
      --spec-type draft-mtp --spec-draft-n-max 4
```

(No Bonsai 2 o drafter MTP **não foi baixado** — ver seção Bonsai.)

---

## MiMo-V2.6 Distill Qwen 9B (XiaomiMiMo — denso, multimodal, reasoning)

Distill do MiMo-V2.6 em base Qwen3.5-9B (arch `qwen35`, DENSA — sem
`-ncmoe`/`--load-mode none`), multimodal (image-text-to-text), ctx nativo
262144, reasoning com `reasoning_content` separado. Origem dos safetensors:
`XiaomiMiMo/MiMo-V2.6-Distill-Qwen-9B` (BF16 ~18,8 GB — não usar direto).
GGUF instalado: bartowski (o oficial `ggml-org/...-GGUF` só publica Q8_0
9,5 GB, que não cabe com o floor 128k na RTX 3060):

```bash
hf download bartowski/MiMo-V2.6-Distill-Qwen-9B-GGUF \
  MiMo-V2.6-Distill-Qwen-9B-Q4_K_M.gguf \
  mmproj-MiMo-V2.6-Distill-Qwen-9B-f16.gguf \
  --local-dir models/MiMo-V2.6-Distill-Qwen-9B-GGUF
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `MiMo-V2.6-Distill-Qwen-9B-Q4_K_M.gguf` | ~5,5 GB | entry `MiMo2.6_9B` |
| `mmproj-MiMo-V2.6-Distill-Qwen-9B-f16.gguf` | ~0,9 GB | visão (mmproj) |

> **SEM MTP**: header do GGUF sem tensors `nextn` (verificado; 0 vs 4 no
> Ornith 1.5 9B). Drafts comunitários (`VitreousCut/...-MTP-GGUF`) existem
> mas não instalados — precedente DSpark: aceitação baixa.

> Sampling do `generation_config.json` oficial: temp 0.6 / top-p 0.95 /
> top-k 20. Medido (2026-10-20, RTX 3060 12 GB, display idle): **decode
> ~47-51 tok/s, prefill ~1800 tok/s @2,6k**; VRAM 9510 MiB @128k; visão
> validada.

---

## Batch 2026-10-26 — alternativas ao Qwen3.6 35B (5 modelos + 1 bloqueado)

Instalados para testar alternativas ao Qwen3.6 35B-A3B (todos arch
`qwen3_5_moe`, exceto o K2). Receita padrão: macro pdcache + KV q5_1 +
`--load-mode none` + `-ncmoe 31` + `-ub 2048` (regra 7).

```bash
hf download InternScience/Sage-A1.5-Q4_K_M-GGUF \
  Sage-A1.5-Q4_K_M.gguf Sage-A1.5-mmproj.gguf \
  --local-dir models/Sage-A1.5-Q4_K_M

hf download abenzerps/Apodex-1.1-mini-GGUF \
  Apodex-1.1-mini-Q4_K_M.gguf mmproj-Apodex-1.1-mini-F16.gguf \
  --local-dir models/Apodex-1.1-mini-Q4_K_M

hf download bartowski/nex-agi_Nex-N2.5-mini-GGUF \
  nex-agi_Nex-N2.5-mini-Q4_K_M.gguf mmproj-nex-agi_Nex-N2.5-mini-f16.gguf \
  --local-dir models/Nex-N2.5-mini-Q4_K_M

hf download mradermacher/BigBang-v1-GGUF \
  BigBang-v1.Q4_K_M.gguf BigBang-v1.mmproj-f16.gguf \
  --local-dir models/BigBang-v1-Q4_K_M
```

| Entry | Modelo (origem GGUF) | Sampling oficial | Medido 2026-10-26 |
|-------|----------------------|------------------|-------------------|
| `SageA1.5_35B` | Sage-A1.5 (oficial InternScience) | temp 1.0 / top-p 0.95 / top-k 20 / presence 1.5 | decode ~34 tok/s; VRAM 9849 MiB; thinking |
| `Apodex1.1_35B` | Apodex-1.1 mini (abenzerps; oficial = NVFP4) | temp 1.0 / top-k 20 / top-p 0.95 | decode ~39 tok/s; VRAM 9849 MiB |
| `NexN2.5_35B` | Nex-N2.5 mini (bartowski) | temp 0.7 / top-p 0.95 / top-k 40 | decode ~36 tok/s; VRAM 10609 MiB |
| `BigBangv1_35B` | BigBang v1 (mradermacher) | temp 1.0 / top-k 20 / top-p 0.95 | decode ~37 tok/s; VRAM 10625 MiB |

> **K2-Horizon 36B MoVA — REMOVIDO em 2026-10-26 (política do floor de
> contexto)**: foi instalado e validado (decode ~16-18 tok/s, VRAM
> 10665 MiB), mas o KV de 192 KiB/tok (48 camadas full-attention, 8 KV
> heads × 128) + os 64 experts MoVA fixos na GPU limitavam o ctx a **40k**
> — abaixo do mínimo de 128k. GGUF apagado. Re-baixável se a política
> mudar: `hf download IFM/K2-Horizon-MoVA-36B-A4B-GGUF
> K2-Horizon-MoVA-36B-A4B-Q4_K_M.gguf` (receita validada: `-c 40960
> -ncmoe 47` + macro pdcache).
>
> **Raon-1 mini 30B (KRAFTON): BLOQUEADO** — arch `raon1_mini` não existe
> no llama.cpp master nem em fork conhecido (avaliado em 2026-10-26).
> Reavaliar se um PR for aceito.
>
> Os 4 qwen3_5_moe são thinking/reasoning — orçar `max_tokens` generoso.

---

## Recursive Flint 40B-A2.5B (RecursiveSI — MoE agêntico de código, texto puro)

MoE 39,8B total / ~2,5B ativos (49 camadas = 2 densas + 47 MoE; 256 experts
top-6 + 1 shared; 35 camadas SWA janela 513 + 14 full-attention — só estas
guardam KV completo, ~28 KiB/tok em f16, o que deixa o floor 128k leve com
KV q5_1). Vocab 150144, ctx nativo 262144, reasoning + tool calls
multi-turno. **Texto apenas — sem mmproj; SEM MTP/draft** (não publica head
nextn). Requer llama.cpp ≥ PR ggml-org#30928 (merge 2026-10-21, arch
`flint`): imagem stock atualizada para o build 11804 (`c7fc50941`) e engine
pdcache reconstruída no MESMO commit (pin acompanhado em
`engines/llama.cpp-pdcache/`).

GGUF oficial do ggml-org (23,4 GB — mesmo padrão MoE híbrido do Qwen3.6 35B):

```bash
hf download ggml-org/Flint-GGUF Flint-Q4_K_M.gguf --local-dir models/Flint-GGUF
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `Flint-Q4_K_M.gguf` | ~23,4 GB | entry `Flint_40B_A2.5B` |

Entry com `docker-pdcache` + `--load-mode none` + `-ncmoe 38` (de 47 camadas
MoE; regra 2) + `-ub 2048` (regra 7). Sampling do model card: temp 1.0 /
top-p 0.95 / top-k 20. Orçar `max_tokens` generoso — modelo reasoning
(recomendação oficial: até ~32k tokens de saída em problemas difíceis).
Nota do PR: workaround de scaling das ativações de experts custa 10-30% de
desempenho (a otimizar upstream). **Validado em 2026-10-22** (RTX 3060 12
GB, display idle, fingerprint `b1-c7fc509`): **decode ~42 tok/s curto /
~38 @1,7k, prefill ~850 tok/s @1,7k; VRAM 9583 MiB @128k** (~2,7 GB de
folga). `-ncmoe 36` testado: decode idêntico dentro do ruído com +830 MiB
de VRAM — mantido 38. Carga fria a partir do NVMe: ~30 s.

---

## Flint 40B-A2.5B Uncensored (Heretic — decensurado, texto puro)

Mesmo Recursive Flint de cima, decensurado pelo **electroglyph** via Heretic
(abliterated: recusas 98/100 → 5/100 no teste do autor). GGUF Q4_K_M
convertido pelo Octopusman388 a partir dos safetensors BF16 (mesma arch
`flint`, requer llama.cpp ≥ PR ggml-org#30928 — já atendido pela imagem em
uso). Origem: `Octopusman388/flint-uncensored-GGUF`:

```bash
hf download Octopusman388/flint-uncensored-GGUF \
  flint-uncensored-Q4_K_M.gguf \
  --local-dir models/Flint-Uncensored-GGUF
```

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `flint-uncensored-Q4_K_M.gguf` | ~24,2 GB (22,5 GiB) | entry `Flint_40B_A2.5B_Uncensored` |

Entry **idêntica à do Flint base** (mesma receita: `docker-pdcache` +
`--load-mode none` + `-ncmoe 38` + `-ub 2048`, sampling temp 1.0 /
top-p 0.95 / top-k 20) com um acréscimo obrigatório:

> ⚠️ **Known issue do autor — reasoning descontrolado ("looping")**: em
> prompts sensíveis o modelo pode divagar no raciocínio por 10k+ caracteres
> sem responder (estocástico; NÃO é loop de tokens nem problema de
> template/EOS). Mitigação validada pelo autor (4/4 runs): limitar o thinking
> com `--reasoning-budget 4096 --reasoning-budget-message "I have thought
> enough. I will now answer directly."` — incluída na entry. O budget limita
> o drift, não o elimina; presence-penalty NÃO ajuda.

> Validado aqui em 2026-10-24 (RTX 3060 12 GB, display idle): **decode
> ~37 tok/s, VRAM pico 9874 MiB @128k** (~2,4 GB de folga) — paridade com o
> Flint base. Modelo reasoning: consome muitos tokens de raciocínio (700
> tokens de max_tokens foram inteiros no reasoning em pergunta simples) —
> orçar `max_tokens` generoso.

---

Após instalar + entry + `./manage.sh restart`, verifique:

```bash
# Listar entries
curl http://localhost:8081/v1/models

# Testar inferência (o primeiro request dispara a carga do container)
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "NOME_DO_MODELO",
    "messages": [{"role": "user", "content": "Olá!"}],
    "temperature": 0.7
  }'

# Logs do container do modelo (enquanto Up)
docker logs ls-NOME_DO_MODELO
```

> Se a carga falhar com `exit 125` na primeira tentativa após restart, é o
> flake documentado no README/AGENTS (troubleshooting): repetir o request ou
> `./manage.sh restart`.

---

## Modelos de Difusão (ComfyUI)

Os modelos de imagem do ComfyUI vivem em `models/comfyui/` (montado em
`/root/ComfyUI/models` do container `comfyui`) e são versionados **fora** do
git (mesma regra dos GGUFs). Stack atual: **Qwen-Image 2.1 Turbo**
(7B DiT, 8 passos, CFG 1 — geração e edição no mesmo modelo).

```bash
# Difusão — int8_convrot oficial (principal; nativo do ComfyUI, mais rápido em Ampere)
hf download Comfy-Org/Qwen-Image-2.1 \
  diffusion_models/qwen_image_2.1_turbo_int8_convrot.safetensors \
  --local-dir models/comfyui

# Text encoder — Qwen3-VL 8B w4a8 (variante de menor VRAM)
hf download Comfy-Org/Qwen-Image-2.1 \
  text_encoders/qwen3vl_8b_w4a8.safetensors \
  --local-dir models/comfyui

# VAE
hf download Comfy-Org/Qwen-Image-2.1 \
  vae/qwen_image_2.1_vae_bf16.safetensors \
  --local-dir models/comfyui
```

Alternativas oficiais no mesmo repo (`Comfy-Org/Qwen-Image-2.1`): difusão
`_bf16` (14,2 GB) / `_int8_convrot` (não-turbo, 25+ passos); text encoder
`_bf16` / `_int8_convrot`. Não baixar os encoders de prompt-enhancement
(`qwen3.5_9b_*_pe_*`) — opcionais nos templates e ~5 GB cada.

Depois de baixar: `docker restart comfyui` (o ComfyUI escaneia os diretórios
no boot). Workflows API e mapeamento: `../DOCKER.md` (seção comfyui).

---

## Dicas

- **Quantização**: Q4_K_M é o ponto de equilíbrio entre qualidade e tamanho. Q3 pode perder qualidade, Q5/Q6 é mais pesado sem ganho significativo.
- **Contexto**: `-c` maior consome mais memória. Use 49152 como padrão, 65536 apenas se a GPU permitir (meta do plano: ctx ≥ 64k razoável; Bonsai PTQ1_0 validado a 65536 com ~9,1 GiB de VRAM no processo).
- **Flash Attention**: já vem ativado nas macros (`-fa on`).
- **Monitorar VRAM**: Use `nvidia-smi` para verificar o uso de memória durante a inferência.
