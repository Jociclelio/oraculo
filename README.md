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
| llama.cpp **stock** | `ghcr.io/ggml-org/llama.cpp:full-cuda` | todos os modelos clássicos (Gemma, Qwen, Ornith, PE) |
| llama.cpp **fork PrismML** (dedicada) | `llama.cpp-prismml:latest` — build local em [`engines/llama.cpp-prismml/`](engines/llama.cpp-prismml/), commit pinado `84445367f` | GGUFs ternários **Bonsai 2 27B** — regra **nunca stock** (kernels ternários + Hadamard são exclusivos do fork) |
| **Strata** (Qwen3.8-Flash-Next) | `strata:latest` — build local em [`strata/`](strata/), commit pinado `61b3fb5dd` | **Qwen3.8-Flash-Next Coder IQ1_M** — instalado em `/home/jocic/strata-data` (NVMe); entry `Strata` ativa |

> **Posicionamento: stack para 1 usuário por vez.** Todas as entries usam
> `-np 1`; entradas paralelas (`np>1`) só como exceção pontual para modelos
> pequenos (exemplo comentado no fim do `llama-swap/config.yaml`).

> **Meta de performance**: prefill/decode razoável com **contexto ≥ 64k**
> (128k quando a VRAM e o prefill permitirem). Medido no Bonsai PTQ1_0 @
> ctx 65536 (mmproj carregado, RTX 3060 12 GB): prefill ≈ **540 tok/s**,
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
[`models/MODELS_INSTALL.md`](models/MODELS_INSTALL.md)):

```
models/
├── Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced/
├── Ornith-1.5-9B-Q4_K_M/
├── Ornith-1.5-35B-A3B-Q4_K_M/
├── Qwen3.6-28B-REAP20-A3B-Q4_K_M/
├── Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/
├── Ternary-Bonsai-2-27B-gguf/          # Bonsai 2 (PTQ1_0/PQ2_0/mmproj)
├── unsloth_Qwen3.6_35B_A3B/
└── unsloth_Qwen3.6_35B_A3B_MTP/
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

## Decisões de Projeto

### Hardware compartilhado — autonomia sob demanda

O Oráculo roda na **mesma GPU que a máquina de uso pessoal** (RTX 3060 12GB, que já divide VRAM com o display/Wayland). Por isso, o design é deliberadamente **request-driven, não autônomo**:

- **Nenhum agente roda sozinho em background** — não há Hermes, n8n nem workflows agendados que possam carregar um modelo e requerer VRAM quando a placa está ocupada com outra atividade (jogo, render, etc.)
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

Gateway WhatsApp com MCP Streamable HTTP em `http://localhost:2785/mcp`. A API key é gerada na primeira inicialização:

```bash
docker exec openwa cat /app/data/.api-key
```

Já conectado ao Open WebUI como **tool server MCP**. Para usar no opencode/pi, adicionar como MCP streamable-http com header `X-API-Key`.

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
| `./manage.sh stop` | Desligar TUDO: llama-swap (SIGTERM → SIGKILL) + `docker compose down` |
| `./manage.sh restart` | Parar e iniciar novamente (tudo) |
| `./manage.sh status` | llama-swap + `docker compose ps` |
| `./manage.sh swap {start\|stop\|restart}` | Só o llama-swap (não toca no compose) |
| `./manage.sh services {start\|stop}` | Só os serviços auxiliares (compose) |
| `tail -f logs/llama-swap.log` | Logs do proxy llama-swap (swap, health checks) |
| `docker logs ls-<Modelo>` | Logs do container do modelo carregado no momento |
| `docker logs open-webui` | Ver logs do open-webui |
| `./manage.sh unload` | Descarregar modelos `ls-*` (libera VRAM p/ ComfyUI) |

---

## Modelos Disponíveis

Fonte de verdade: [`llama-swap/config.yaml`](llama-swap/config.yaml)
(17 entries: 15 stock + 2 Bonsai).

| Modelo | Contexto | Notas |
|--------|----------|-------|
| Gemma4_12B | 49152 | Multimodal (texto) |
| Gemma4_12B_MTP | 64000 | MTP speculative decoding / cache split q8_0 (target) + f16 (draft); máx. validado 192K |
| Gemma4_12B_Hauhau | 49152 | Multimodal (texto, imagem, áudio) |
| Gemma4_12B_Agentic | 49152 | Denso 12B 100% VRAM / agentic-terminal-tool-use / ~24 tok/s |
| Mellum2.1_12B_A2.5B | 49152 | MoE pequeno 100% VRAM / código thinking / ~90 tok/s |
| LFM2.5_8B_A1B_Hermes | 49152 | MoE minúsculo 100% VRAM / Hermes agentic / ~129 tok/s |
| Saluki27B_Qwen3.8 | 32768 | Qwen3.8-27B 2-bit (denso 100% VRAM) + head MTP / best tool-calling / ~31 tok/s |
| Qwen3.6_35B_General | 98304 | MoE (32 experts CPU) / head MTP (draft-mtp n=2) / aceitação ~82-93% |
| Qwen3.6_35B_Code | 49152 | MoE (28 experts CPU) / head MTP / temp=0.6 / ~27 tok/s |
| Qwen3.6_35B_It_General | 98304 | MoE (32 experts CPU) / head MTP / temp=0.7 |
| Qwen3.6_35B_It_Reasoning | 98304 | MoE (32 experts CPU) / head MTP / temp=1.0 |
| Ornith1.5_9B_MTP | 65536 | MTP speculative decoding / acceptance ~0.40 |
| Ornith1.5_9B_DFlash | 65536 | DFlash speculative decoding / acceptance ~0.42 |
| Ornith1.5_35B_MTP | 49152 | MoE (28 experts CPU) / MTP / acceptance ~0.80 |
| Qwen3.6_35B_A3B_Hauhau_Aggressive | 98304 | MoE (32 experts CPU) / multimodal |
| bonsai-27b | 65536 | **Bonsai 2 27B PTQ1_0** (primária) + mmproj Q8_0 (visão) — engine PrismML; prefill ≈ 540 tok/s, decode ≈ 24,5 tok/s, VRAM 9146 MiB (processo) |
| bonsai-27b-pq2_0 | 65536 | **Bonsai 2 27B PQ2_0** (secundária, mais rápida em Ampere) — engine PrismML; ctx 65536 sem OOM |
| Xing4.0_29B_A4B | 49152 | MoE 29B/4B (fork shuxiaoqiong 8c379195a) / `--load-mode none` + `-ncmoe 24` / ~12,5 tok/s |
| Strata | 65536 | **Qwen3.8-Flash-Next Coder IQ1_M** (engine Strata) / pesos+pack em `/home/jocic/strata-data` (NVMe) / **~30 GB RAM travados** — nunca junto de outro modelo / carga 1-3 min / ~10 tok/s decode, prefill ~8 tok/s |

> **Strata (Qwen3.8-Flash-Next)**: instalada em 2026-10-11 (variante Coder
> IQ1_M — a única que cabe nos 32 GB da máquina). O swap do llama-swap é
> obrigatório: ao pedir `Strata`, o modelo anterior é descarregado (libera
> ~30 GB de RAM); ao pedir outro, o container do Strata é removido.
> Detalhes: [`strata/README.md`](strata/README.md).

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
| [`strata/README.md`](strata/README.md) | Engine/instalação Strata (Qwen3.8-Flash-Next) — instalada, entry ativa |
