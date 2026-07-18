# Oráculo

Servidor local de LLMs com **llama.cpp** (inferência GPU), interface **Open WebUI**, gateway **OpenWA** (WhatsApp API com MCP) e automação **n8n** (workflows com MCP). Expondo:

- **API OpenAI-compatible** (llama.cpp) → porta `8081`
- **Open WebUI** → porta `8080`
- **OpenWA API + MCP** → porta `2785` (localhost apenas)
- **n8n** → porta `5678`

---

## Requisitos

### Hardware

| Componente | Mínimo | Recomendado | Testado |
|------------|--------|-------------|---------|
| **GPU** | NVIDIA com 8 GB VRAM | NVIDIA com 24+ GB VRAM | NVIDIA RTX 3090 (24 GB) |
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
├── Bonsai-27B-Q1_0/
├── Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced/
├── Ornith-1.0-35B-GGUF/
├── ornith-1.0-9b-Q4_K_M/
├── Qwen3.5-9B-UD-Q4_K_XL/
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

# Verificar OpenWA
curl http://localhost:2785/api/health/ready

# Acessar n8n
# Abrir http://localhost:5678 no navegador
```

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

> O Open WebUI está pré-configurado para conectar ao llama-cpp na porta 8081.

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
| `docker logs openwa` | Ver logs do openwa |
| `docker logs n8n` | Ver logs do n8n |

## OpenWA — WhatsApp com MCP

O OpenWA expõe ~39 ferramentas de WhatsApp via **MCP Streamable HTTP** para uso no Open WebUI:

| Item | Valor |
|------|-------|
| **URL API** | `http://localhost:2785` |
| **Endpoint MCP** | `POST http://localhost:2785/mcp` |
| **Container** | `openwa` |
| **Porta** | `2785` (127.0.0.1 — localhost apenas) |

### Configurar MCP no Open WebUI

1. Acesse **http://localhost:8080** como admin
2. **⚙️ Admin Settings → External Tools → + (Add Server)**
3. **Type**: `MCP (Streamable HTTP)`
4. **Server URL**: `http://localhost:2785/mcp`
5. **Auth**: `Bearer <API_KEY>` (obter com `docker exec openwa cat /app/data/.api-key`)
6. **Save** → reiniciar se solicitado

> Use **MCP (Streamable HTTP)**, não OpenAPI. OpenAPI causa crash na UI.

Ferramentas disponíveis: list/get sessions, send messages (text/image/video/audio), chats, contacts, groups, webhooks.

---

## n8n — Automação de Workflows

Interface de automação com +300 integrações (Slack, Gmail, GitHub, Notion, etc.) e **MCP nativo**.

| Item | Valor |
|------|-------|
| **URL** | `http://localhost:5678` |
| **Endpoint MCP** | `http://localhost:5678/mcp-server/http` |
| **Container** | `n8n` |
| **Porta** | `5678` (modo host) |

### Configurar MCP do n8n no Open WebUI

1. Acesse **http://localhost:5678** e crie uma conta admin
2. Vá em **Settings → Instance-level MCP** e ative **Enable MCP access**
3. Clique em **Connection details** e copie o **Access Token** (ou configure OAuth2)
4. Habilite workflows individuais para MCP: abra o workflow → `...` → **Settings** → **Available in MCP**
5. Acesse **http://localhost:8080** como admin no Open WebUI
6. **⚙️ Admin Settings → External Tools → + (Add Server)**
7. **Type**: `MCP (Streamable HTTP)`
8. **Server URL**: `http://localhost:5678/mcp-server/http`
9. **Auth**: `Bearer <YOUR_N8N_MCP_TOKEN>` (token obtido no passo 4)
10. **Save** → reiniciar se solicitado

> Use **MCP (Streamable HTTP)**, não OpenAPI. OpenAPI causa crash na UI.

Ferramentas MCP disponíveis: search/get/execute workflows, gerenciar credenciais, nodes, projetos, execuções, data tables.

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
| Gemma4_12B_Hauhau | 49152 | Multimodal (texto, imagem, áudio) |
| Qwen3.6_28B_A3B | 49152 | MoE (28 experts CPU) |
| Qwen3.6_35B_General | 49152 | MoE / temp=1.0 |
| Qwen3.6_35B_Code | 49152 | MoE / temp=0.6 |
| Qwen3.6_35B_It_General | 49152 | MoE / temp=0.7 |
| Ornith1.0_9B | 65536 | Contexto expandido |
| Ornith_1.0_35B | 49152 | MoE / temp=0.6 |
| Bonsai-27B_Q1_0 | 49152 | Alta compressão |

Configurações completas em [`models.ini`](models.ini).

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
