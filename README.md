# Oráculo

Servidor local de LLMs com **llama.cpp** (inferência GPU) e interface **Open WebUI**. Expondo:

- **API OpenAI-compatible** (llama.cpp) → porta `8081`
- **Open WebUI** → porta `8080`
- **Open Terminal** (execução agêntica) → porta `8000`
- **SearXNG** (busca web privada) → porta `8888`
- **OpenWa** (gateway WhatsApp + MCP) → porta `2785`

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

Coloque os arquivos `.gguf` nos respectivos diretórios:

```
models/
├── Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced/
├── Ornith-1.5-9B-Q4_K_M/
├── Ornith-1.5-35B-A3B-Q4_K_M/
├── Qwen3.6-28B-REAP20-A3B-Q4_K_M/
├── Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/
├── unsloth_Qwen3.6_35B_A3B/
└── unsloth_Qwen3.6_35B_A3B_MTP/
```

### 4. Iniciar os serviços

```bash
# Iniciar com Docker Compose (recomendado)
docker compose up -d

# Ou usar o script de gerenciamento
cd llama-cpp-server
./manage.sh start
```

### 5. Verificar que está rodando

```bash
# Status dos containers
docker compose ps

# Testar API
curl http://localhost:8081/v1/models

# Acessar Open WebUI
# Abrir http://localhost:8080 no navegador


```

---

## Decisões de Projeto

### Hardware compartilhado — autonomia sob demanda

O Oráculo roda na **mesma GPU que a máquina de uso pessoal** (RTX 3060 12GB, que já divide VRAM com o display/Wayland). Por isso, o design é deliberadamente **request-driven, não autônomo**:

- **Nenhum agente roda sozinho em background** — não há Hermes, n8n nem workflows agendados que possam carregar um modelo e requerer VRAM quando a placa está ocupada com outra atividade (jogo, render, etc.)
- **O humano está sempre no loop**: modelos só carregam quando há requisição e são **descarregados após 5 min de ociosidade** (`sleep-idle-seconds`), devolvendo a VRAM
- Sistemas de automação (n8n) foram testados e removidos do stack por esse motivo

> **Tradeoff consciente**: autonomia total (agents 24/7, pipelines agendados) exige um substrato dedicado. Com uma máquina dedicada a inferência no futuro, workflows autônomos passam a fazer sentido — até lá, o controle fica com o usuário.

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

---

## Open WebUI

Interface web para interagir com os modelos via navegador.

| Item | Valor |
|------|-------|
| **URL** | `http://localhost:8080` |
| **Container** | `open-webui` |
| **Porta** | `8080` (modo host) |

> O Open WebUI está pré-configurado para conectar ao llama-cpp na porta 8081 e usar o SearXNG como busca web.

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

## Gerenciamento

| Comando | Descrição |
|---------|-----------|
| `./manage.sh start` | Iniciar servidor llama-cpp |
| `./manage.sh stop` | Parar servidor llama-cpp |
| `docker compose up -d` | Iniciar todos os serviços |
| `docker compose down` | Parar todos os serviços |
| `docker compose ps` | Ver status |
| `docker logs llama-cpp` | Ver logs do llama-cpp |
| `docker logs open-webui` | Ver logs do open-webui |


---

## Trocar Modelo

```bash
# Carregar modelo específico
curl -X POST http://localhost:8081/v1/load_model \
  -H "Content-Type: application/json" \
  -d '{"model_alias": "Qwen3.6_35B_General"}'

# Unload modelo atual
curl -X POST http://localhost:8081/v1/unload_model
```

---

## Modelos Disponíveis

| Modelo | Contexto | Notas |
|--------|----------|-------|
| Gemma4_12B | 49152 | Multimodal (texto) |
| Gemma4_12B_MTP | 64000 | MTP speculative decoding / cache split q8_0 (target) + f16 (draft); máx. validado 192K |
| Gemma4_12B_Hauhau | 49152 | Multimodal (texto, imagem, áudio) |
| Qwen3.6_28B_A3B | 49152 | MoE (28 experts CPU) |
| Qwen3.6_35B_General | 98304 | MoE (32 experts CPU) / temp=1.0 |
| Qwen3.6_35B_General_VL | 49152 | MoE (28 experts CPU) / mmproj pendente |
| Qwen3.6_35B_Code | 49152 | MoE (28 experts CPU) / temp=0.6 |
| Qwen3.6_35B_It_General | 98304 | MoE (32 experts CPU) / temp=0.7 |
| Qwen3.6_35B_It_Reasoning | 98304 | MoE (32 experts CPU) / temp=1.0 |
| Ornith1.5_9B_MTP | 65536 | MTP speculative decoding / acceptance ~0.40 |
| Ornith1.5_9B_DFlash | 65536 | DFlash speculative decoding / acceptance ~0.42 |
| Ornith1.5_35B_MTP | 49152 | MoE (28 experts CPU) / MTP / acceptance ~0.80 |
| Qwen3.6_35B_A3B_Hauhau_Aggressive | 98304 | MoE (32 experts CPU) / multimodal |
| PE_T2I_Heretic | 16384 | Text-to-image / alias `pe-t2i` |
| PE_I2I_Heretic | 16384 | Image-to-image (visão) / alias `pe-i2i` |

Configurações completas em [`models/models.ini`](models/models.ini).

---

## Troubleshooting

### GPU não é reconhecida

```bash
# Verificar NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi
```

### Modelo não carrega

```bash
# Verificar se o arquivo .gguf existe
docker exec llama-cpp ls -la /models/

# Ver logs
docker logs llama-cpp
```

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
| [`models/models.ini`](models/models.ini) | Configuração dos modelos |
