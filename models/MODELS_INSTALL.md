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
├── Ornith-1.5-9B-Q4_K_M/
│   └── Ornith-1.5-9B-Q4_K_M.gguf
├── Ornith-1.5-35B-A3B-Q4_K_M/
│   └── Ornith-1.5-35B-A3B-Q4_K_M.gguf
├── Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced/
│   └── modelo.gguf
├── Ternary-Bonsai-2-27B-gguf/          # Bonsai 2 (ver seção própria abaixo)
│   ├── Ternary-Bonsai-2-27B-PTQ1_0.gguf
│   └── Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf
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
entry sem sufixo = 64k (floor, `-c 65536`); contexto maior = sufixo `_XXk`
(ex.: `Gemma4_12B_128k` = `-c 131072`); abaixo do floor = sufixo `_32k`
(ex.: `Saluki27B_Qwen3.8_32k`).

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

> ⚠️ **Regra dura — nunca engine stock**: GGUFs ternários PTQ1_0/PQ2_0 só
> funcionam no fork **PrismML-Eng/llama.cpp** (kernels ternários + Hadamard).
> A imagem stock recusa esses quantizados ou carrega como `Q2_0` legacy
> gerando lixo. A entry `bonsai-27b` usa a imagem
> local `llama.cpp-prismml:latest` (build em `engines/llama.cpp-prismml/`,
> fork pinado no commit `84445367f`). Se a imagem não existir, construa:
> `./engines/llama.cpp-prismml/build.sh`.

> **MTP do Bonsai não foi baixado** (arquivo draft MTP ~7 GB no repo
> upstream; fora de escopo do plano llama-swap-multi-engine). As entries
> atuais não usam `--model-draft`.

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
[`../strata/`](../strata/) (Dockerfile pinado + `README.md` com os passos de
instalação futura) e a entry `Strata:` permanece **comentada** no
`llama-swap/config.yaml`. Para ativar: seguir `strata/README.md` e
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
VRAM junto do target (`-devd none`/`-ngld 0` abortam no scheduler). O GGUF do
draft (413 MB) ficou em `models/MiniCPM-V-4.7-35B-A3B-DSpark/` para reteste
futuro. A entry serve **sem** speculative decoding.

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

## Verificação

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
