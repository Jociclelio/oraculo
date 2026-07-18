# Docker — Stack Oraculo (llama-cpp + Open WebUI + OpenWA)

Stack Docker com **llama.cpp** (inferência GPU), **Open WebUI** (interface web), **OpenWA** (WhatsApp API com MCP) e **n8n** (automação de workflows com MCP).

---

## Requisitos

- **Docker** e **Docker Compose** instalados
- **NVIDIA Container Toolkit** configurado (GPU NVIDIA)
- Mínimo **10 GB** de disco livre (por modelo)
- Mínimo **2 GB** de RAM livre (OpenWA + Chromium)
- Mínimo **1 GB** de RAM livre (n8n)

---

## Serviços

### llama-cpp — Inferência GPU

- **Imagem**: `ghcr.io/ggml-org/llama.cpp:full-cuda`
- **Container**: `llama-cpp`
- **Porta**: `8081`
- **GPU**: 1× NVIDIA GPU
- **Volume**: `./models → /models` (modelos GGUF)
- **Config**: `./models/models.ini → /app/models.ini`

Serve uma **API OpenAI-compatible** para geração de texto, chat e embeddings.

### open-webui — Interface Web

- **Imagem**: `ghcr.io/open-webui/open-webui:main`
- **Container**: `open-webui`
- **Porta**: `8080` (rede host)
- **Volume**: `open-webui-data → /app/backend/data`
- **Dependência**: `llama-cpp`
- **Rede**: `host`

Interface web para interagir com os modelos. Configurada para conectar ao llama-cpp via `http://localhost:8081/v1`.

**Variáveis de ambiente**:

| Variável | Valor | Descrição |
|----------|-------|-----------|
| `OAI_API_BASE` | `http://localhost:8081/v1` | URL da API llama.cpp |
| `WEBUI_SECRET_KEY` | (gerado) | Chave secreta para persistência de tokens OAuth/MCP |

> **Importante**: `WEBUI_SECRET_KEY` é obrigatório em Docker. Sem ele, ferramentas MCP conectadas via OAuth perdem tokens entre reinicializações.

### openwa — WhatsApp API Gateway com MCP

- **Imagem**: `ghcr.io/rmyndharis/openwa:main`
- **Container**: `openwa`
- **Porta**: `2785` (127.0.0.1:2785 — localhost apenas)
- **Rede**: `openwa-network` + `openwa-internal-docker`
- **Volumes**: `openwa-data → /app/data`, `openwa-sessions → /app/data/sessions`

Gateway WhatsApp com ~39 ferramentas expostas via **MCP Streamable HTTP** em `POST /mcp`.

**Variáveis de ambiente**:

| Variável | Valor | Descrição |
|----------|-------|-----------|
| `MCP_ENABLED` | `true` | Habilita servidor MCP |
| `MCP_READONLY` | `false` | false = expor ferramentas de escrita |
| `AUTO_START_SESSIONS` | `false` | Auto-reconectar sessões no boot |
| `DOCKER_HOST` | `tcp://openwa-docker-proxy:2375` | Proxy Docker socket |

### openwa-docker-proxy — Proxy Seguro do Docker Socket

- **Imagem**: `tecnativa/docker-socket-proxy:v0.4.2`
- **Container**: `openwa-docker-proxy`
- **Rede**: `openwa-internal-docker` (internal, sem acesso externo)

Proxy restrito que expõe apenas: CONTAINERS, IMAGES, VOLUMES, INFO, PING, POST, DELETE. É o **único** container com acesso ao Docker socket.

### n8n — Automação de Workflows com MCP

- **Imagem**: `docker.n8n.io/n8nio/n8n`
- **Container**: `n8n`
- **Porta**: `5678` (rede host)
- **Volume**: `n8n_data → /home/node/.n8n`
- **Rede**: `host`

Interface de automação com +300 integrações (Slack, Gmail, GitHub, Notion, etc.). **MCP nativo** exposto em `http://localhost:5678/mcp-server/http`.

**Configuração inicial obrigatória**:
1. Acesse http://localhost:5678 e crie conta admin
2. **Settings → Instance-level MCP** → ative **Enable MCP access**
3. Clique em **Connection details** → copie o **Access Token**
4. Habilite workflows para MCP: workflow → `...` → **Settings** → **Available in MCP**

**Ferramentas MCP disponíveis**:
- **Workflow**: search, get, execute, test, publish, unpublish, create_from_code, update
- **Execução**: get_execution, search_executions
- **Dados**: list_credentials, search_projects, search_folders, list_tags
- **Nodes**: search_nodes, get_node_types, resolve_node_data
- **SDK**: get_sdk_reference, validate_workflow, validate_nodes, get_guidance

**Acesso**: http://localhost:5678

**Variáveis de ambiente**:

| Variável | Valor | Descrição |
|----------|-------|-----------|
| `GENERIC_TIMEZONE` | `America/Sao_Paulo` | Fuso horário do container |
| `TZ` | `America/Sao_Paulo` | Fuso horário do sistema |
| `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS` | `true` | Segurança de arquivos de config |

> **MCP**: Para conectar n8n ao Open WebUI, adicione um MCP server do tipo `MCP (Streamable HTTP)` apontando para `http://localhost:5678/mcp-server/http` com auth `Bearer <token>`.

---

## Redes

```
┌─────────────────────────────────────────────────────────────┐
│                    Host Network                              │
│  llama-cpp (8081) ←→ open-webui (8080) ←→ openwa (2785)     │
│  n8n (5678) (todos network_mode: host)                       │
│                                                              │
│  openwa (127.0.0.1:2785) ←→ Open WebUI via localhost         │
│  n8n (5678) ←→ Open WebUI via localhost                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              openwa-internal-docker (internal)               │
│  openwa ←→ openwa-docker-proxy:2375                         │
│  (sem acesso externo — apenas comunicação interna)           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    openwa-network                            │
│  openwa ←→ openwa-docker-proxy (comunicação)                │
│  openwa ←→ serviços externos (se necessário)                │
└─────────────────────────────────────────────────────────────┘
```

---

## Gerenciamento

### Docker Compose (todos os serviços)

```bash
# Iniciar todos os serviços
docker compose up -d

# Parar todos os serviços
docker compose down

# Parar e remover volumes (CUIDADO: perde dados)
docker compose down -v

# Ver status
docker compose ps

# Ver logs
docker compose logs -f

# Reiniciar serviço específico
docker compose restart openwa
```

### Script de gerenciamento (apenas llama-cpp)

```bash
# Iniciar servidor llama-cpp
./manage.sh start

# Parar servidor llama-cpp
./manage.sh stop
```

---

## API OpenAI-Compatible

### Endpoints

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| `/v1/models` | GET | Lista modelos configurados |
| `/v1/chat/completions` | POST | Chat / geração de texto |
| `/v1/embeddings` | POST | Embeddings |

### Exemplos

```bash
# Listar modelos
curl http://localhost:8081/v1/models

# Chat
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.6_35B_Code",
    "messages": [{"role": "user", "content": "Olá!"}],
    "temperature": 0.7
  }'
```

### Usar com biblioteca OpenAI (Python)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8081/v1",
    api_key="llama-cpp-local"
)

response = client.chat.completions.create(
    model="Qwen3.6_35B_General",
    messages=[{"role": "user", "content": "Teste"}],
    temperature=0.7
)
print(response.choices[0].message.content)
```

---

## OpenWA — WhatsApp API + MCP

### Acessar API REST

```bash
# Health check
curl http://localhost:2785/api/health/ready

# Dashboard (mesma porta)
open http://localhost:2785
```

### Configurar MCP no Open WebUI

1. Acesse **http://localhost:8080**
2. **⚙️ Admin Settings → External Tools → + (Add Server)**
3. **Type**: `MCP (Streamable HTTP)`
4. **Server URL**: `http://localhost:2785/mcp`
5. **Auth**: `Bearer <API_KEY>` (obter com `docker exec openwa cat /app/data/.api-key`)
6. **Save** → reiniciar Open WebUI se solicitado

### Obter API Key

```bash
# API key gerada na primeira inicialização
docker exec openwa cat /app/data/.api-key
```

### Testar MCP via curl

```bash
API_KEY=$(docker exec openwa cat /app/data/.api-key)

# Listar ferramentas disponíveis
curl -X POST http://localhost:2785/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

### Gerenciar Sessões WhatsApp

```bash
# Listar sessões
curl -H "Authorization: Bearer $API_KEY" \
  http://localhost:2785/api/sessions

# Criar nova sessão (QR code)
curl -X POST -H "Authorization: Bearer $API_KEY" \
  http://localhost:2785/api/sessions \
  -d '{"name": "default"}'
```

---

## Gerenciar Modelos

O servidor suporta múltiplos modelos no `models.ini`, mas carrega apenas 1 por vez (`--models-max 1`).

```bash
# Carregar modelo
curl -X POST http://localhost:8081/v1/load_model \
  -H "Content-Type: application/json" \
  -d '{"model_alias": "Qwen3.6_35B_General"}'

# Unload modelo atual
curl -X POST http://localhost:8081/v1/unload_model
```

---

## Open WebUI

Acessar a interface web em **http://localhost:8080**.

Primeiro acesso: criar conta de administrador. O Open WebUI já vem configurado para conectar ao llama-cpp automaticamente.

Para adicionar outros backends de API, ir em **Settings → Connections → OpenAI API** e configurar:

| Campo | Valor |
|-------|-------|
| API Base URL | `http://localhost:8081/v1` |
| API Key | `llama-cpp-local` |

---

## Estrutura de Dados

```
oraculo/
├── models/                   # Modelos GGUF (compartilhados)
│   ├── Bonsai-27B-Q1_0/
│   ├── Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced/
│   ├── Ornith-1.0-35B-GGUF/
│   ├── ornith-1.0-9b-Q4_K_M/
│   ├── Qwen3.5-9B-UD-Q4_K_XL/
│   ├── Qwen3.6-28B-REAP20-A3B-Q4_K_M/
│   ├── Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/
│   ├── unsloth_Qwen3.6_35B_A3B/
│   ├── unsloth_Qwen3.6_35B_A3B_MTP/
│   ├── models.ini            # Configuração dos modelos do llama.cpp
│   └── MODELS_INSTALL.md     # Guia de instalação de modelos
│
├── docker-compose.yml        # Definição dos serviços
├── manage.sh                 # Script de gerenciamento (llama-cpp)
├── .env                      # Variáveis de ambiente
├── DOCKER.md                 # Documentação Docker
└── README.md                 # Guia rápido de uso
```

---

## Backup

```bash
# Backup da config dos modelos
tar -czf models-config-backup.tar.gz models/models.ini

# Backup do Open WebUI
docker exec open-webui tar -czf /tmp/openwebui-backup.tar.gz /app/backend/data

# Backup do OpenWA (sessões + dados)
docker exec openwa tar -czf /tmp/openwa-backup.tar.gz /app/data

# Restaurar
tar -xzf models-config-backup.tar.gz
```

---

## Troubleshooting

### GPU não é reconhecida

```bash
# Verificar NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi

# Verificar se o container tem acesso à GPU
docker inspect llama-cpp | grep -A5 GPU
```

### Modelo não carrega

```bash
# Verificar se o arquivo .gguf existe no volume
docker exec llama-cpp ls -la /models/

# Ver logs
docker logs llama-cpp
```

### Storage cheio

```bash
# Verificar uso
du -sh models/*/

# Limpar modelos não usados
rm -rf models/NOME_DO_MODELO/
```

### Logs

```bash
# Logs do llama-cpp
docker logs llama-cpp

# Logs do open-webui
docker logs open-webui

# Logs do openwa
docker logs openwa

# Logs do docker-proxy
docker logs openwa-docker-proxy
```

### Open WebUI não conecta ao llama-cpp

```bash
# Verificar se ambos estão rodando
docker compose ps

# Verificar se a API está respondendo
curl http://localhost:8081/v1/models

# Verificar conexão do open-webui para o llama-cpp
docker exec open-webui curl -s http://localhost:8081/v1/models

# Reiniciar o open-webui
docker restart open-webui
```

### OpenWA não inicia

```bash
# Verificar logs
docker logs openwa

# Verificar se o docker-proxy está acessível
docker exec openwa curl -s http://openwa-docker-proxy:2375/containers/json

# Verificar se a porta 2785 está livre
ss -tlnp | grep 2785
```

### MCP não aparece no Open WebUI

```bash
# Verificar se o endpoint MCP está respondendo
API_KEY=$(docker exec openwa cat /app/data/.api-key)
curl -X POST http://localhost:2785/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'

# Verificar se o MCP está habilitado
docker exec openwa grep MCP_ENABLED /app/data/.env.generated || echo "MCP_ENABLED=true"

# Reiniciar open-webui após adicionar MCP server
docker restart open-webui
```

### OpenWA perde conexão com WhatsApp

```bash
# Verificar status da sessão
curl -H "Authorization: Bearer $API_KEY" \
  http://localhost:2785/api/sessions

# Reiniciar sessão problemática
curl -X POST -H "Authorization: Bearer $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}/restart
```
