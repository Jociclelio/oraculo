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
> (padrão em todas as entries desde 2026-10-15, com KV quantizado
> `-ctk q5_1 -ctv iq4_nl`). Medido no Bonsai PTQ1_0 @ ctx 65536
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
(27 entries: 22 stock/pdcache + 4 bonsai PrismML + 1 Xing).

| Modelo | Contexto | Notas |
|--------|----------|-------|
| Gemma4_12B | 131072 | Multimodal (visão + áudio nativo) QAT |
| LFM2.5_24B_A2B | 131072 | LiquidAI MoE 24B/2,45B raciocínio agêntico; ncmoe 20; **~45 tok/s, prefill ~1900 tok/s**; temp 0.1/top-k 50/rep 1.05 |
| MiniCPM-V_4.7_35B | 131072 | **MiniCPM-V 4.7 35B-A3B** multimodal (OpenBMB; backbone Qwen3.6); sem MTP; ncmoe 32 + ub 4096; **~32-35 tok/s, prefill ~1600 tok/s**; visão validada |
| MiniCPM-V_4.7_1B | 131072 | **MiniCPM-V 4.7 1B** multimodal (OpenBMB); variante edge densa; **decode ~200 tok/s, prefill ~8,5k tok/s**; visão validada |
| Ornith1.5_9B | 131072 | **Ornith-1.5-9B** (ornith-ai) denso, raciocínio agêntico; MTP self-draft n=2; **decode ~50 tok/s, prefill ~1,5k tok/s, aceitação ~0,53-0,69** |
| Qwen3.6_35B_General | 131072 | MoE (32 experts CPU) / head MTP (draft-mtp n=2) / aceitação ~82-93% |
| Qwen3.6_35B_Code | 131072 | MoE (29 experts CPU) / head MTP / temp=0.6 / **~27 tok/s, prefill ~890 tok/s** |
| Qwen3.6_35B_It_General / _It_Reasoning | 131072 | Instruct (sem/temp thinking); MoE 32 experts CPU |
| Qwen3.6_35B_A3B_Hauhau_Aggressive | 131072 | Uncensored Aggressive, multimodal; ncmoe 29; **prefill ~1150 tok/s, decode ~39 tok/s** |
| Ornith1.5_35B_MTP | 131072 | Agêntico (APEX Compact); MoE 28 experts CPU; aceitação ~0,80 |
| SageA1.5_35B | 131072 | **Sage-A1.5 35B-A3B** (InternScience) multimodal; thinking; **~34 tok/s** |
| Apodex1.1_35B | 131072 | **Apodex 1.1 mini 35B-A3B** multimodal; **~39 tok/s** — o mais rápido do zoológico 35B |
| NexN2.5_35B | 131072 | **Nex-N2.5 mini 35B** multimodal; reasoning_effort; **~36 tok/s** |
| BigBangv1_35B | 131072 | **BigBang v1 35B-A3B** multimodal; thinking; **~37 tok/s** |
| K2Horizon_36B_MoVA_40k | 40960 | **K2-Horizon MoVA 36B-A4B** (IFM) texto puro; KV gigante → teto 40k; **~16-18 tok/s** |
| bonsai-27b | 131072 | **Bonsai 2 27B PTQ1_0** + mmproj Q8_0 (visão) — engine PrismML; **24,5 tok/s** @ 64k |
| Xing4.0_29B_A4B | 131072 | MoE 29B/4B + MLA + mHC — engine Xing (fork shuxiaoqiong); ncmoe 27; **~12,5 tok/s** @ 64k |

### Categorias

Por **modelo** (não por entry); um modelo pode ter mais de uma categoria.
Detalhes e justificativas em [`AGENTS.md`](AGENTS.md#categorias-de-modelos-por-modelo-não-por-entry).

- **SmallMoE** (MoE com offload de experts p/ RAM): LFM2.5-24B-A2B,
  MiniCPM-V 4.7 35B, Qwen3.6-35B, Ornith-1.5-35B, Nemotron-3.5-Bolt-74B,
  Flint-40B, Xing4.0-29B, Sage-A1.5 35B, Apodex-1.1 mini, Nex-N2.5 mini,
  BigBang v1, K2-Horizon 36B (Raon-1 mini bloqueado: sem suporte no
  llama.cpp)
- **Tiny** (cabem 100% na VRAM em ~4-bit): Gemma4-12B, MiniCPM-V 4.7 1B,
  Ornith-1.5-9B, Qwen3.5-9B, MiMo-V2.6-9B
- **SuperCompressed** (sub-Q4_K_M e 100% VRAM): LFM2.5-24B-A2B (IQ2_M),
  Bonsai 2 27B, Bonsai 2 9B (PTQ1_0 ternários)
- **Uncensored**: Qwen3.6-35B Hauhau, Qwen3.5-9B HauhauCS, Flint-40B Heretic,
  Bonsai 27B Heretic, Bonsai 9B Uncensored

> **Contexto e KV**: entry SEM sufixo = **128k** (floor, `-c 131072`),
> viabilizado pelo KV cache quantizado `-ctk q5_1 -ctv q5_1` (tipo ÚNICO —
> K/V misto quebra os híbridos GDN, ver AGENTS.md regra 10) + `-fa on` em
> todas as entries. Modelo que não alcança 128k =
> sufixo `_XXk` com o maior contexto validado por carga real. Ver
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
