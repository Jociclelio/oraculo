# Oráculo

Servidor local de LLMs com **llama-swap** (proxy multi-engine que gerencia
containers efêmeros de **llama.cpp** para inferência GPU) e interface
**Open WebUI**. Expondo:

- **API OpenAI-compatible** (proxy llama-swap) → porta `8081`
- **Open WebUI** → porta `8080`
- **Open Terminal** (execução agêntica) → porta `8000`
- **SearXNG** (busca web privada) → porta `8888`
- **OpenWa** (gateway WhatsApp + MCP) → porta `2785`
- **Playwright MCP** (navegador p/ o Open WebUI) → porta `8931`
- **Memory MCP** (grafo de conhecimento p/ Open WebUI + opencode) → porta `8932`
- **ComfyUI** (geração/edição de imagens, Qwen-Image 2.1 Turbo) → porta `8188`
- **9Router** (proxy de fallback cloud p/ LLMs free/API-key) → porta `20128`

---

## Serving — llama-swap (processo de host)

O antigo serviço Docker `llama-cpp` (container fixo + `models.ini`) foi
substituído pelo **[llama-swap](https://github.com/mostlygeek/llama-swap)**:
um proxy que roda no **host** em `127.0.0.1:8081` e gerencia **um container
Docker efêmero por modelo** (`docker run --rm`, nome `ls-<Modelo>`):

- **Swap automático**: pedir um modelo descarrega o anterior (só 1 carregado
  por vez — equivalente ao antigo `--models-max 1`);
- **Descarga por ociosidade**: `ttl: 300` s (substitui o `sleep-idle-seconds`);
- **Configuração por modelo**: entries em [`llama-swap/config.yaml`](llama-swap/config.yaml)
  (substitui o `models/models.ini`, agora histórico/desativado).

Três engines por baixo:

| Engine | Imagem | Uso |
|--------|--------|-----|
| llama.cpp **stock** | `ghcr.io/ggml-org/llama.cpp:full-cuda` | todos os modelos clássicos (Gemma, Qwen, LFM, MiniCPM, Ornith) |
| llama.cpp **fork PrismML** (dedicada) | `llama.cpp-prismml:latest` — build local em [`engines/llama.cpp-prismml/`](engines/llama.cpp-prismml/), commit pinado `84445367f` | GGUFs ternários **Bonsai 2 27B** — regra **nunca stock** (kernels ternários + Hadamard são exclusivos do fork) |
| llama.cpp **fork Xing** (dedicada) | `llama.cpp-xing:latest` — build local em [`engines/llama.cpp-xing/`](engines/llama.cpp-xing/), commit pinado `8c379195a` | **Xing4.0 29B-A4B** — arquitetura `xing4_0` só no fork shuxiaoqiong (PR ggml-org#29012 não mergeado) |

> **Posicionamento: stack para 1 usuário por vez.** Todas as entries usam
> `-np 1`; entradas paralelas (`np>1`) só como exceção pontual para modelos
> pequenos (exemplo comentado no fim do `llama-swap/config.yaml`).

> **Meta de performance**: prefill/decode razoável com **contexto ≥ 128k**
> (padrão em todas as entries desde 2026-10-15, com KV quantizado —
> `-ctk q4_0 -ctv q4_0` desde 2026-10-27; q5_1 antes). Medido no Bonsai
> PTQ1_0 @ ctx 65536
> (mmproj carregado, RTX 3060 12 GB): prefill ≈ **540 tok/s**,
> decode ≈ **24,5 tok/s**, VRAM **9146 MiB** no processo / **10657 MiB**
> total na GPU — sem OOM.

---

## Requisitos

### Hardware

| Componente | Mínimo | Recomendado | Testado |
|------------|--------|-------------|---------|
| **GPU** | NVIDIA com 8 GB VRAM | NVIDIA com 24+ GB VRAM | NVIDIA RTX 3060 (12 GB) |
| **RAM** | 18 GB | 34 GB+ | 32 GB |
| **Disco** | 50 GB livre | 100 GB+ | — |

> Modelos quantizados (Q4_K_M) rodam com ~8-12 GB VRAM. Modelos MoE (35B-A3B) beneficiam-se de mais VRAM para melhor throughput.

### Software

- **Docker** e **Docker Compose** instalados
- **NVIDIA Container Toolkit** configurado para suporte a GPU
- **Git** (para clonar o repositório)
- **llama-swap** — binário de release instalado por `./llama-swap/install.sh`
  (baixa a última release para `bin/`; o `manage.sh` exige `bin/llama-swap`)

---

## Instalação

### 1. Clonar o repositório

```bash
git clone <url-do-repo>
cd oraculo
```

### 2. Verificar Docker e GPU

```bash
# Verificar Docker
docker --version
docker compose version

# Verificar acesso à GPU
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi
```

### 3. Baixar modelos

Coloque os arquivos `.gguf` nos respectivos diretórios (guia completo em
[`models/MODELS_INSTALL.md`](models/MODELS_INSTALL.md) — os dirs atuais são
exatamente os referenciados pelas entries do `config.yaml`):

```
models/
├── LFM2.5-24B-A2B-GGUF/
├── MiniCPM-V-4.7-35B-A3B-Q4_K_M/
├── MiniCPM-V-4.7-1B-Q4_K_M/                 (+ mmproj f16)
├── Ornith-1.5-9B-Q4_K_M/                    (+ mmproj BF16)          (+ mmproj f16)
├── Ornith-1.5-35B-MTP-APEX-Compact/
├── Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/  (+ mmproj f16)
├── Ternary-Bonsai-2-27B-gguf/             # Bonsai 2 (PTQ1_0/mmproj)
├── unsloth_Qwen3.6_35B_A3B_MTP/           # usado por 8 entries Qwen3.6
├── Xing4.0-29B-A4B-Q4_K_M/
└── gemma-4-12B-it-qat-UD-Q4_K_XL/         (+ mmproj F32)
```

### 4. Instalar o llama-swap (binário)

```bash
./llama-swap/install.sh    # baixa a última release para bin/llama-swap
```

### 5. Iniciar os serviços

```bash
# Sobe TUDO: llama-swap (proxy de serving, porta 8081) + serviços auxiliares
# (Open WebUI, Open Terminal, SearXNG, ComfyUI, MCPs, OpenWa via compose)
./manage.sh start
```

### 6. Verificar que está rodando

```bash
# Status: llama-swap (pidfile em logs/llama-swap.pid) + docker compose ps
./manage.sh status

# Testar API (lista as entries do config.yaml)
curl http://localhost:8081/v1/models

# Acessar Open WebUI
# Abrir http://localhost:8080 no navegador
```

---

## Estrutura do repositório

Tudo relacionado ao oraculo vive dentro da pasta do repo (sem dependência de
volumes nomeados do Docker nem de pastas espalhadas no sistema):

```
oraculo/
├── data/                 # ESTADO dos serviços (gitignored — backupar, não versionar)
│   ├── open-webui/       #   webui.db (config/usuários/chats), uploads, RAG
│   ├── open-terminal/    #   workspace do agente
│   ├── openwa/           #   DB + sessões WhatsApp + .api-key
│   ├── 9router/          #   providers/contas
│   ├── comfyui/          #   caches hf/torch (re-baixáveis)
│   ├── hermes/           #   HERMES_HOME (memória, skills, sessões, config.yaml)
│   └── searxng/          #   settings.yml (secret_key)
├── models/               # GGUFs (re-baixáveis — ver MODELS_INSTALL.md)
├── engines/              # builds das engines dedicadas (prismml, xing; strata sem pesos)
├── llama-swap/           # config.yaml — fonte da verdade dos modelos
├── logs/  mcp-data/  comfyui/  bin/
├── manage.sh  docker-compose.yml  .env
└── AGENTS.md  README.md  DOCKER.md
```

**O que é insubstituível vs. re-baixável:**

| Pasta | Conteúdo | Se perder |
|-------|----------|-----------|
| `data/` | estado real (banco, chats, sessões) | **insubstituível** — incluir no backup |
| `models/` | GGUFs | re-baixável do Hugging Face |
| `engines/` | infra de build | re-construível (`build.sh`/Dockerfile pinados) |
| `logs/`, caches | runtime | dispensável |

> **Gotcha do `webui.db`**: variáveis como `WEBSEARCH_ENGINE`,
> `TERMINAL_SERVER_CONNECTIONS` e conexões MCP são persistidas no banco na
> primeira inicialização — depois disso **o banco vence o env**. Mudanças de
> integração = editar a UI admin ou o `data/open-webui/webui.db`, não o compose.

---

## Decisões de Projeto

### Hardware compartilhado — autonomia sob demanda

O Oráculo roda na **mesma GPU que a máquina de uso pessoal** (RTX 3060 12GB, que já divide VRAM com o display/Wayland). Por isso, o design é deliberadamente **request-driven, não autônomo**:

- **Nenhum agente roda sozinho em background enquanto o PC está em uso** — o design continua request-driven. A **única exceção** é o Hermes Agent (Nous Research), container `hermes` sob o porteiro `bin/hermes-gate.sh`: ele **só acorda com a tela bloqueada** (hyprlock) e sem jogo na GPU, e **para imediatamente** quando o humano volta — mesmo estado "jogo rodando → VRAM livre" que o gpu-shim e o sleep de 180 s do llama-swap já garantem no resto do stack (detalhes em `DOCKER.md` → seção hermes)
- **O humano está sempre no loop**: modelos só carregam quando há requisição e são **descarregados após 5 min de ociosidade** (`ttl: 300` no llama-swap), devolvendo a VRAM
- Sistemas de automação (n8n) foram testados e removidos do stack por esse motivo

> **Tradeoff consciente**: autonomia total (agents 24/7, pipelines agendados) exige um substrato dedicado. Com uma máquina dedicada a inferência no futuro, workflows autônomos passam a fazer sentido — até lá, o controle fica com o usuário.

### Single-user — paralelismo só como exceção

O stack é dimensionado para **1 usuário por vez**: cada entry sobe com
`-np 1` e o swap mantém um único modelo carregado. `np>1` existe no config
apenas como exemplo comentado, para modelos pequenos — dobrar slots exige
dobrar KV cache/VRAM, o que a RTX 3060 12 GB não comporta nos modelos
grandes daqui.

---

## Uso

### Chat com curl

```bash
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.6_35B_Code",
    "messages": [{"role": "user", "content": "Olá, como você está?"}],
    "temperature": 0.7
  }'
```

### Chat com Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8081/v1",
    api_key="llama-cpp-local"
)

response = client.chat.completions.create(
    model="Qwen3.6_35B_Code",
    messages=[{"role": "user", "content": "Explique o que é um transformer"}],
    temperature=0.7
)

print(response.choices[0].message.content)
```

### Trocar de modelo

Automático: basta apontar o request para outro `model` — o llama-swap
descarrega o modelo anterior e sobe o novo (container efêmero). Não há mais
`load_model`/`unload_model` nem edição de `models.ini`; os parâmetros de cada
modelo vivem em [`llama-swap/config.yaml`](llama-swap/config.yaml).

---

## Open WebUI

Interface web para interagir com os modelos via navegador.

| Item | Valor |
|------|-------|
| **URL** | `http://localhost:8080` |
| **Container** | `open-webui` |
| **Porta** | `8080` (modo host) |

> O Open WebUI está pré-configurado para conectar ao proxy llama-swap na porta 8081 e usar o SearXNG como busca web.

## Open Terminal

Substrato de execução para o agente do Open WebUI: shell, filesystem e execução de código em container isolado.

| Item | Valor |
|------|-------|
| **API** | `http://localhost:8000` |
| **Container** | `open-terminal` |
| **Conexão** | Pré-configurada como "Oraculo Terminal" (via `TERMINAL_SERVER_CONNECTIONS`) |

Uso no chat: clicar no ícone de nuvem (☁) no input e selecionar **Oraculo Terminal**. Requer modelo com *Function Calling = Native*. Detalhes em [`DOCKER.md`](DOCKER.md).

## SearXNG

Metabuscador privado usado como motor de busca web do Open WebUI (web search sem API paga).

```bash
# Testar busca via JSON
curl "http://localhost:8888/search?q=teste&format=json"
```

## OpenWa (WhatsApp)

Gateway WhatsApp com MCP Streamable HTTP em `http://localhost:2785/mcp`. A API key é gerada na primeira inicialização e fica em `data/openwa/.api-key` (host) / `/app/data/.api-key` (container):

```bash
cat data/openwa/.api-key
# ou: docker exec openwa cat /app/data/.api-key
```

Já conectado ao Open WebUI como **tool server MCP**. Para usar no opencode/pi, adicionar como MCP streamable-http com header `X-API-Key`.

## 9Router (fallback cloud)

Proxy de roteamento para **providers cloud de LLM** — camada opcional e
complementar ao serving local (llama-swap, que é a prioridade). Agrega 40+
providers atrás de um endpoint OpenAI-compatible único, com fallback
automático: `http://localhost:20128/v1` (dashboard em
`http://localhost:20128/dashboard`, senha = `INITIAL_PASSWORD` do `.env`).

- **Free tiers**: OpenCode Free (**bloqueado na origem** — `403 FreeTierError`
  fora do cliente OpenCode) e Kiro (~50 créditos/mês, OAuth interativo).
- **API-key**: OpenRouter, Gemini, Groq, NVIDIA NIM, GLM, MiniMax… — conectar
  em *Dashboard → Providers*. Ativo: **Gemini** (key do pi, free tier,
  validado e2e). Detalhes e estado dos providers: [`DOCKER.md`](DOCKER.md).
- **Uso**: apontar o Open WebUI (Admin > Connections > OpenAI API) ou o opencode para `http://localhost:20128/v1` com a API key gerada no dashboard; modelos com prefixo do provider (ex.: `oc/...`, `kr/...`).

> **Posicionamento**: conveniência, NÃO infraestrutura — os modelos "free"
> mudam/desaparecem sem aviso; o serving local continua sendo o caminho
> primário. Prompts que passarem por ele saem da rede local para os
> providers cloud. Detalhes em [`DOCKER.md`](DOCKER.md).

---

## MCP no Open WebUI

O Open WebUI aceita MCP **só via Streamable HTTP**, então os servidores stdio
rodam como serviços do compose atrás de uma ponte HTTP. Quatro conexões
registradas (Admin > Integrations > External Tool Servers; ficam no `webui.db`,
que tem precedência sobre o env):

| Ferramenta | URL | Para que serve |
|-----------|-----|----------------|
| `context7` | `https://mcp.context7.com/mcp` | documentação atualizada de libs/APIs |
| `playwright` | `http://localhost:8931/mcp` | navegador real: abrir, clicar, preencher, screenshot |
| `memory` | `http://localhost:8932/mcp` | grafo de conhecimento persistente (compartilhado com o opencode via `mcp-data/memory.json`) |
| `openwa` | `http://localhost:2785/mcp` | WhatsApp (ver acima) |

No chat, ativar a ferramenta no seletor de ferramentas. Detalhes e gotchas:
`DOCKER.md`.

---

## Geração de imagens (ComfyUI)

Serviço `comfyui` (porta `8188`) roda o **Qwen-Image 2.1 Turbo** (7B DiT
int8_convrot, 8 passos, CFG 1) para geração e edição de imagens, integrado ao
Open WebUI (engine `comfyui`, já configurada no `webui.db`).

No chat do Open WebUI: ativar **Imagem** no menu de integrações do campo de
mensagem e pedir a imagem; para editar, anexar a imagem e descrever a
mudança. A UI nativa do ComfyUI fica em `http://localhost:8188`.

**VRAM compartilhada, liberação automática nos dois sentidos**: ao pedir
uma imagem com um LLM carregado, o gpu-shim (na frente do ComfyUI) avalia a
VRAM e descarrega o llama-swap (`GET /unload`) antes de gerar; ao terminar,
o ComfyUI devolve a VRAM (`--disable-smart-memory`, sobra ~190 MiB) e o
próximo chat recarrega o LLM sozinho. Liberação manual: `./manage.sh unload`.

Detalhes (modelos, workflows, mapeamento de nós): `DOCKER.md` e
`models/MODELS_INSTALL.md`.

---

## Gerenciamento

| Comando | Descrição |
|---------|-----------|
| `./manage.sh start` | Iniciar TUDO: llama-swap em background + `docker compose up -d` |
| `./manage.sh stop` | Desligar TUDO: llama-swap (SIGTERM → SIGKILL) + `docker compose down` + remove containers de modelo `ls-*` (sem isso eles viram órfãos retendo VRAM) |
| `./manage.sh restart` | Parar e iniciar novamente (tudo) |
| `./manage.sh status` | llama-swap + `docker compose ps` |
| `./manage.sh swap {start\|stop\|restart}` | Só o llama-swap (não toca no compose) |
| `./manage.sh services {start\|stop}` | Só os serviços auxiliares (compose) |
| `tail -f logs/llama-swap.log` | Logs do proxy llama-swap (swap, health checks) |
| `docker logs ls-<Modelo>` | Logs do container do modelo carregado no momento |
| `docker logs open-webui` | Ver logs do open-webui |
| `./manage.sh unload` | Descarregar modelos `ls-*` (libera VRAM p/ ComfyUI) |
| `watch -n 2 ./bin/dashboard.sh` | Dashboard de terminal: modelo ativo, prefill/decode (último request), VRAM da GPU |

O `bin/dashboard.sh` é one-shot (sem dependências além de `docker`,
`nvidia-smi`, `awk`/`sed`): lê o container `ls-*` ativo, o contexto do
entry direto do `config.yaml`, as últimas taxas medidas pelo llama-server
(linhas `slot print_timing` do `docker logs`) e a VRAM total da GPU
(inclui desktop/jogos — GPU compartilhada). Indica idle quando nada está
carregado (ttl de 5 min). Também funciona sem `watch`, para consulta única.

---

## Modelos Disponíveis

Fonte de verdade: [`llama-swap/config.yaml`](llama-swap/config.yaml)
(23 entries: 18 stock/pdcache + 4 bonsai PrismML + 1 Xing).

Medições **pós-unlock** (2026-10-26, gpu-unlock BF16 ativo): decode = 200
tokens gerados com ctx ~0; prefill = prompt sintético @2k (`n_predict=1`);
VRAM = pico `nvidia-smi` (total, incl. ~800 MiB do display) na carga real
@128k. Decode @ctx longo tende a cair nos híbridos (curvas em
[`benchmarks/`](benchmarks/)).

| Entry | Ctx | Decode | Prefill @2k | VRAM | Categorias | Notas |
|-------|-----|--------|-------------|------|------------|-------|
| Qwen3.6_35B_A3B | 131072 | ~35 tok/s | ~1000 tok/s | 11200 MiB | SmallMoE | thinking + head MTP (aceitação ~57%); multimodal; **única entry Qwen3.6** (Code/It_* removidas 2026-10-26) |
| Qwen3.6_35B_A3B_Hauhau_Aggressive | 131072 | ~41 tok/s | ~1100 tok/s | 11240 MiB | SmallMoE + Uncensored | multimodal; sem MTP |
| LFM2.5_24B_A2B | 131072 | ~46 tok/s | ~1640 tok/s | 10602 MiB | SmallMoE | raciocínio agêntico; temp 0.1/top-k 50/rep 1.05 |
| LFM2.5_24B_A2B_IQ2_M | 131072 | **~106 tok/s** | ~2960 tok/s | 10632 MiB | SmallMoE + SuperCompressed | 100% GPU (7,5 GB); **o mais rápido do zoo** |
| MiniCPM-V_4.7_35B | 131072 | ~36 tok/s | ~1150-1620 tok/s | 10598 MiB | SmallMoE | multimodal; visão validada; ncmoe 32 + ub 4096 |
| SageA1.5_35B | 131072 | ~34 tok/s | ~1000 tok/s | 9849 MiB | SmallMoE | multimodal; thinking (consome max_tokens) |
| Apodex1.1_35B | 131072 | ~39 tok/s | ~940 tok/s | 9849 MiB | SmallMoE | multimodal; o mais rápido do zoo 35B |
| NexN2.5_35B | 131072 | ~36 tok/s | ~900 tok/s | 10609 MiB | SmallMoE | multimodal; thinking via reasoning_effort |
| BigBangv1_35B | 131072 | ~37 tok/s | ~970 tok/s | 10625 MiB | SmallMoE | multimodal; thinking |
| Ornith1.5_35B_MTP | 131072 | ~32 tok/s | ~1140 tok/s | 11564 MiB | SmallMoE | multimodal; MTP self-draft (aceitação ~38%); agêntico |
| Flint_40B_A2.5B | 131072 | ~41 tok/s | ~1300 tok/s | 10734 MiB | SmallMoE | código agêntico; texto puro; ub 4096 (calibração) |
| Flint_40B_A2.5B_Uncensored | 131072 | ~43 tok/s | ~880 tok/s | 10764 MiB | SmallMoE + Uncensored | texto puro; reasoning-budget ativo |
| Nemotron3.5_Bolt_74B | 131072 | ~16-19 tok/s | ~560 tok/s | ~11100 MiB | SmallMoE | híbrido Mamba (arch `nemotron_h_moe`); ncmoe 74 + mmproj na CPU; sem draft |
| Xing4.0_29B_A4B | 131072 | ~28 tok/s | ~580 tok/s | 10916 MiB | SmallMoE | MLA + mHC; engine Xing dedicada (fork pinado) |
| Gemma4_12B | 131072 | ~40 tok/s | ~1250 tok/s | 9314 MiB | Tiny | multimodal (visão + áudio nativo); QAT; thinking |
| MiniCPM-V_4.7_1B | 131072 | **~248 tok/s** | **~10,4k tok/s** | 10620 MiB | Tiny | multimodal; visão validada; recorde de prefill do zoo |
| Ornith1.5_9B | 131072 | ~58 tok/s | ~1600 tok/s | 10244 MiB | Tiny | multimodal; MTP self-draft n=2; agêntico |
| Qwen3.5_9B_HauhauCS | 131072 | ~55 tok/s | ~1800 tok/s | 10255 MiB | Tiny + Uncensored | multimodal |
| MiMo2.6_9B | 131072 | ~53 tok/s | ~1615 tok/s | 9508 MiB | Tiny | multimodal; reasoning separado |
| bonsai-27b | 131072 | ~27 tok/s | ~530 tok/s | 10538 MiB | SuperCompressed | PTQ1_0 ternário; engine PrismML; KV q4_0; visão validada |
| bonsai-27b-heretic | 131072 | ~26 tok/s | ~530 tok/s | 10544 MiB | SuperCompressed + Uncensored | sem pdcache/sleep (patch só no master) |
| bonsai-9b | 196608 | ~84 tok/s | ~1530 tok/s | 10870 MiB | SuperCompressed | PTQ1_0 ternário; KV bf16 @192k; visão validada |
| bonsai-9b-uncensored | 196608 | ~78 tok/s | ~1560 tok/s | 10886 MiB | SuperCompressed + Uncensored | LoRA AtomicChat rank-1 (3,2 MB); thinking pesado |

### Categorias

Por **modelo** (não por entry); um modelo pode ter mais de uma categoria.
Detalhes e justificativas em [`AGENTS.md`](AGENTS.md#categorias-de-modelos-por-modelo-não-por-entry).

- **SmallMoE** (MoE com offload de experts p/ RAM): LFM2.5-24B-A2B,
  MiniCPM-V 4.7 35B, Qwen3.6-35B, Ornith-1.5-35B, Nemotron-3.5-Bolt-74B,
  Flint-40B, Xing4.0-29B, Sage-A1.5 35B, Apodex-1.1 mini, Nex-N2.5 mini,
  BigBang v1 (Raon-1 mini bloqueado: sem suporte no llama.cpp; K2-Horizon
  removido: contexto máx. 40k < floor 128k)
- **Tiny** (cabem 100% na VRAM em ~4-bit): Gemma4-12B, MiniCPM-V 4.7 1B,
  Ornith-1.5-9B, Qwen3.5-9B, MiMo-V2.6-9B
- **SuperCompressed** (sub-Q4_K_M e 100% VRAM): LFM2.5-24B-A2B (IQ2_M),
  Bonsai 2 27B, Bonsai 2 9B (PTQ1_0 ternários)
- **Uncensored**: Qwen3.6-35B Hauhau, Qwen3.5-9B HauhauCS, Flint-40B Heretic,
  Bonsai 27B Heretic, Bonsai 9B Uncensored

### IZ — Índice Zoo (métrica de desempenho, 0-100+)

Nota de desempenho que combina decode e ingestão da janela pelo **elo mais
fraco** (`min` dos fatores): um modelo é tão usável quanto o pior dos dois.
Cada fator vira uma nota 0-1+ por interpolação piecewise com 3 âncoras de
usabilidade, e a IZ extrapola acima do "excelente" (notas >100 = superior):

| Ancoragem | Decode | Tempo p/ ler a janela toda |
|---|---|---|
| **Não usável** | 25 t/s | 320 s (~3 min) |
| **Confortável** | 50 t/s | 128 s |
| **Excelente (IZ = 100)** | 100 t/s | 32 s (⇔ 4096 t/s @128k) |

```
D(d):  d≤25 → 0,25·(d/25)   |  25-50 → 0,25+0,5·(d-25)/25
       50-100 → 0,75+0,25·(d-50)/50   |  d>100 → 1,0+(d-100)/100
P(t):  t≥320 → 0,25·(320/t) |  128-320 → 0,75-0,5·(t-128)/192
       32-128 → 0,75+0,25·(128-t)/96   |  t<32 → 1,0+(32-t)/32
t_janela = ctx_tokens ÷ prefill_tps  (janela PRÓPRIA do modelo)
IZ = 100 × min(D, P)
```

Propriedades: **IZ ≥ 75 ⇔ decode ≥ 50 t/s E ingestão ≤ 128 s** (confortável
nos dois); **IZ ≥ 100 ⇔ decode ≥ 100 t/s E ingestão ≤ 32 s**; qualquer fator
na zona não-usável derruba a nota para <25 — o outro fator não salva.

| # | Entry | Decode | t p/ ler a janela | **IZ** | O que limita |
|---|---|---|---|---|---|
| 1 | MiniCPM-V_4.7_1B | 248 t/s | 12,6 s (128k) | **160,7** | — (superior) |
| 2 | LFM2.5_24B_A2B_IQ2_M | 106 t/s | 44,3 s (128k) | **96,8** | prefill quase excelente |
| 3 | Ornith1.5_9B | 58 t/s | 81,9 s | **79,0** | decode |
| 4 | Qwen3.5_9B_HauhauCS | 55 t/s | 72,8 s | **77,5** | decode |
| 5 | MiMo2.6_9B | 53 t/s | 81,2 s | **76,5** | decode |
| 6 | bonsai-9b-uncensored | 78 t/s | 126,0 s (192k) | **75,5** | prefill |
| 7 | bonsai-9b | 84 t/s | 128,5 s (192k) | **74,9** | prefill |
| 8 | Gemma4_12B | 40 t/s | 104,9 s | **70,0** | decode |
| 9 | LFM2.5_24B_A2B | 46 t/s | 79,9 s | **67,0** | decode |
| 10 | Flint_40B_A2.5B_Uncensored | 43 t/s | 148,9 s | **61,0** | equilibrado-médio |
| 11 | Flint_40B_A2.5B | 41 t/s | 100,8 s | **57,0** | decode |
| 12 | Qwen3.6_35B_A3B_Hauhau_Aggressive | 41 t/s | 119,2 s | **57,0** | decode |
| 13 | Apodex1.1_35B | 39 t/s | 139,4 s | **53,0** | decode |
| 14 | BigBangv1_35B | 37 t/s | 135,1 s | **49,0** | decode |
| 15 | NexN2.5_35B | 36 t/s | 145,6 s | **47,0** | decode |
| 16 | MiniCPM-V_4.7_35B | 36 t/s | 114,5 s | **47,0** | decode |
| 17 | Qwen3.6_35B_A3B | 35 t/s | 131,1 s | **45,0** | decode |
| 18 | SageA1.5_35B | 34 t/s | 131,1 s | **43,0** | decode |
| 19 | Ornith1.5_35B_MTP | 32 t/s | 115,0 s | **39,0** | decode |
| 20 | Xing4.0_29B_A4B | 28 t/s | 226,0 s | **31,0** | fraco nos dois |
| 21 | bonsai-27b | 27 t/s | 247,3 s | **29,0** | fraco nos dois |
| 22 | bonsai-27b-heretic | 26 t/s | 247,3 s | **27,0** | fraco nos dois |
| 23 | Nemotron3.5_Bolt_74B | 19 t/s | 234,1 s | **19,0** | **não usável** (decode < 25) |

> Calculada com os números pós-unlock da tabela acima (prefill @2k —
> otimista: híbridos degradam com o contexto; as curvas reais estão em
> [`benchmarks/`](benchmarks/)). Ordenada por IZ.

> **Contexto e KV**: entry SEM sufixo = **128k** (floor, `-c 131072`),
> viabilizado pelo KV cache quantizado `-ctk q4_0 -ctv q4_0` (tipo ÚNICO —
> K/V misto quebra os híbridos GDN, ver AGENTS.md regra 10; default q4_0
> desde 2026-10-27 — o q5_1 anterior não tem kernel de flash attention
> dedicado e era até 2,3× mais lento em decode profundo) + `-fa on` em
> todas as entries. **Modelo que não alcança 128k é removido do zoo**
> (política 2026-10-26; precedente: K2-Horizon 40k). Ver
> [`AGENTS.md`](AGENTS.md) (regra 10).

> **Strata (removida 2026-10-14)**: os pesos (86G) foram apagados na
> limpeza do NVMe e a entry saiu do config; a imagem da engine
> (`strata:latest`) e a infra de build ([`engines/strata/`](engines/strata/))
> ficam preservadas — reativável seguindo o README dela.

---

## Troubleshooting

### GPU não é reconhecida

```bash
# Verificar NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi
```

### Modelo não carrega

```bash
# Verificar se o arquivo .gguf existe em models/
ls -la models/<dir-do-modelo>/

# Ver o log do llama-swap (swap, health checks, erros de carga)
tail -n 50 logs/llama-swap.log

# Ver o log do container do modelo (enquanto estiver Up)
docker logs ls-<Modelo>
```

### Falha intermitente `exit 125` na primeira carga após restart

Flake **recorrente** observado na validação e2e (task 007): a primeira carga
de um modelo após `./manage.sh start` falha às vezes com
`upstream command exited prematurely` (o `docker run` sai com `code=125`);
modelos afetados entre sessões: `Ornith1.5_9B_MTP`, `bonsai-27b`,
`Gemma4_12B`. Em parte das ocorrências o retry/health-check seguinte
recupera sozinho; nas demais, o sucesso só vem em sessão posterior.
**Causa indeterminada** — a hipótese de container órfão por conflito de nome
foi enfraquecida pelo log (o start já executa `docker rm -f ls-<Modelo>`
antes do `docker run` e mesmo assim houve `exit 125`). Workaround imediato:
repetir o request, ou `./manage.sh restart`. Ao reproduzir, capturar o
stderr do `docker run` / `docker events` para diagnóstico (follow-up
registrado no plano).

### Storage cheio

```bash
du -sh models/*/
```

---

## Documentação

| Arquivo | Descrição |
|---------|-----------|
| [`AGENTS.md`](AGENTS.md) | Documentação completa do projeto |
| [`DOCKER.md`](DOCKER.md) | Guia focado em Docker |
| [`llama-swap/config.yaml`](llama-swap/config.yaml) | Entries/parâmetros dos modelos (fonte da verdade) |
| [`models/MODELS_INSTALL.md`](models/MODELS_INSTALL.md) | Instalação de modelos (Bonsai via `hf download`, etc.) |
| [`engines/strata/README.md`](engines/strata/README.md) | Engine Strata (Qwen3.8-Flash-Next) — infra preservada; pesos removidos 2026-10-14 |
