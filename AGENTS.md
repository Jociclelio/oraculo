# oraculo

Servidor local de LLMs com **llama.cpp** (inferência GPU), interface **Open WebUI**, gateway **OpenWA** (WhatsApp API com MCP) e automação **n8n** (workflows com MCP). Expondo:

- **API OpenAI-compatible** (llama.cpp) → porta `8081`
- **Open WebUI** → porta `8080`
- **OpenWA API + MCP** → porta `2785` (localhost apenas)
- **n8n** → porta `5678`

---

## Documentação do Repositório

**Qualquer mudança no repositório deve ser descrita e atualizada nos arquivos de documentação correspondentes.**

- Alterações no `docker-compose.yml` → atualizar `DOCKER.md`
- Alterações no `models.ini` ou modelos → atualizar `AGENTS.md`
- Alterações no `manage.sh` ou fluxo de uso → atualizar `README.md`
- Novos requisitos de hardware/software → atualizar `README.md`

Mantenha a documentação sincronizada com o código. Documentação desatualizada gera confusão e perda de conhecimento.

---

## Estrutura do Repositório

```
oraculo/
├── docker-compose.yml          # Definição dos serviços Docker (llama-cpp, open-webui, openwa, n8n)
├── manage.sh                   # Script de gerenciamento (llama-cpp)
├── .env                        # Variáveis de ambiente
│
├── models/
│   ├── models.ini              # Configurações dos modelos para o servidor llama.cpp
│   ├── MODELS_INSTALL.md       # Guia de instalação de modelos
│   ├── Bonsai-27B-Q1_0/
│   ├── Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced/
│   ├── Ornith-1.0-35B-GGUF/
│   ├── ornith-1.0-9b-Q4_K_M/
│   ├── Qwen3.5-9B-UD-Q4_K_XL/
│   ├── Qwen3.6-28B-REAP20-A3B-Q4_K_M/
│   ├── Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/
│   ├── unsloth_Qwen3.6_35B_A3B/
│   └── unsloth_Qwen3.6_35B_A3B_MTP/
│
├── DOCKER.md                   # Documentação Docker detalhada
└── README.md                   # Guia rápido de uso
```

---

## docker-compose.yml

Define **quatro serviços**: llama-cpp (inferência GPU), open-webui (interface web), openwa (WhatsApp API com MCP) e n8n (automação de workflows com MCP):

### Serviço `llama-cpp` — Servidor de Inferência

| Item          | Valor                                              |
|---------------|-----------------------------------------------------|
| **Imagem**    | `ghcr.io/ggml-org/llama.cpp:full-cuda`            |
| **Container** | `llama-cpp`                                         |
| **Porta**     | `8081`                                              |
| **GPU**       | 1× NVIDIA GPU (via NVIDIA Container Toolkit)       |
| **Volumes**   | `./models → /models` (modelos), `./models.ini → /app/models.ini` (config) |
| **Command**   | `llama-server -s --verbosity 3 --models-preset /app/models.ini --models-max 1 --host 0.0.0.0 --port 8081` |

> O servidor expõe uma API OpenAI-compatible. Use `-s` para modo server-only (sem terminal interativo).

### Serviço `open-webui` — Interface Web

| Item          | Valor                                              |
|---------------|-----------------------------------------------------|
| **Imagem**    | `ghcr.io/open-webui/open-webui:main`              |
| **Container** | `open-webui`                                       |
| **Porta**     | `8080` (network_mode: host)                        |
| **Rede**      | `host`                                             |
| **Volumes**   | `open-webui-data → /app/backend/data`              |
| **Env**       | `OAI_API_BASE=http://localhost:8081/v1`           |

Interface web para interagir com os LLMs via navegador. Configurada para conectar ao llama-cpp automaticamente.

> **Importante**: `WEBUI_SECRET_KEY` é obrigatório em setups Docker. Sem ele, ferramentas MCP conectadas via OAuth não persistem tokens entre reinicializações.

### Serviço `openwa` — WhatsApp API Gateway com MCP

| Item          | Valor                                              |
|---------------|-----------------------------------------------------|
| **Imagem**    | `ghcr.io/rmyndharis/openwa:main`                  |
| **Container** | `openwa`                                           |
| **Porta**     | `2785` (127.0.0.1:2785)                           |
| **Rede**      | `openwa-network` + `openwa-internal-docker`        |
| **Volumes**   | `openwa-data → /app/data`, `openwa-sessions → /app/data/sessions` |
| **Env**       | `MCP_ENABLED=true`, `MCP_READONLY=false`           |

Gateway WhatsApp que expõe ~39 ferramentas via **MCP Streamable HTTP** em `POST /mcp`.

**Ferramentas disponíveis**:
- **Sessão**: list, get, chats, stats, mark read/unread, typing
- **Mensagem**: list, history, reactions, send (text/image/video/audio/document/location/contact/sticker/template), reply, forward, react
- **Contato**: list, get, check-number, resolve-phone, profile-picture, block/unblock
- **Grupo**: list, get, invite-code, create, add participants, set subject/description

**Autenticação**: API key via header `X-API-Key` ou `Authorization: Bearer <key>`. A chave é gerada na primeira inicialização e salva em `openwa-data/.api-key`.

**Modo de operação**: Por padrão, MCP é **read-only**. Defina `MCP_READONLY=false` para expor ferramentas de escrita (enviar mensagens, etc.).

### Serviço `openwa-docker-proxy` — Proxy Seguro do Docker Socket

| Item          | Valor                                              |
|---------------|-----------------------------------------------------|
| **Imagem**    | `tecnativa/docker-socket-proxy:v0.4.2`            |
| **Container** | `openwa-docker-proxy`                              |
| **Rede**      | `openwa-network` + `openwa-internal-docker` (internal) |
| **Volumes**   | `/var/run/docker.sock → /var/run/docker.sock:ro`  |

Proxy restrito que expõe apenas operações necessárias (CONTAINERS, IMAGES, VOLUMES, INFO, PING, POST, DELETE). É o **único** container com acesso ao Docker socket.

### Serviço `n8n` — Automação de Workflows com MCP

| Item          | Valor                                              |
|---------------|-----------------------------------------------------|
| **Imagem**    | `docker.n8n.io/n8nio/n8n`                          |
| **Container** | `n8n`                                              |
| **Porta**     | `5678` (network_mode: host)                        |
| **Rede**      | `host`                                             |
| **Volumes**   | `n8n_data → /home/node/.n8n`                       |
| **Env**       | `GENERIC_TIMEZONE=America/Sao_Paulo`, `TZ=America/Sao_Paulo` |

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

---

## manage.sh

Script de gerenciamento via CLI.

### Uso

```bash
./manage.sh start               # Inicia o servidor llama-cpp
./manage.sh stop                # Para o container llama-cpp
```

### Comportamento interno

| Comando     | Ação                                                          |
|-------------|---------------------------------------------------------------|
| `start`     | Para container existente (se houver), inicia `llama-cpp`      |
| `stop`      | Para e remove o container `llama-cpp`                         |

---

## models.ini

Arquivo de configuração em formato INI para o servidor `llama.cpp`.

### Seção `[*]` — Configurações Globais

Aplicadas a **todos** os modelos:

| Parâmetro        | Valor   | Descrição                                    |
|------------------|---------|----------------------------------------------|
| `cache-type-k`   | `q8_0`  | Tipo de cache para chave (K)                 |
| `cache-type-v`   | `q8_0`  | Tipo de cache para valor (V)                 |
| `cache-reuse`    | `256`   | Tamanho da janela de reuso de contexto       |
| `parallel`       | `1`     | Número de batches paralelos                  |
| `flash-attn`     | `on`    | Ativa flash attention                        |
| `mlock`          | `1`     | Bloqueia memória na RAM (evita swap)         |
| `jinja`          | `1`     | Usa template Jinja para chats                |
| `threads`        | `5`     | Número de threads CPU                        |
| `cache-ram`      | `0`     | Cache RAM (0 = desativado)                   |

### Seções de Modelos

Cada seção `[Nome]` configura um modelo específico com os parâmetros override:

| Parâmetro        | Descrição                                            |
|------------------|------------------------------------------------------|
| `model`          | Caminho ao arquivo `.gguf` do modelo                 |
| `mmproj`         | Arquivo mmproj para multimodal (vision)              |
| `model-draft`    | Modelo draft para MTP (Multi-Token Prediction)       |
| `ctx-size`       | Tamanho do contexto (ex: 49152, 65536)              |
| `ngl`            | Número de camadas na GPU (`all` = todas)             |
| `temp`           | Temperatura de geração (ex: 1.0)                     |
| `top-p`          | Amostragem top-p (ex: 0.95)                          |
| `top-k`          | Amostragem top-k (ex: 64)                            |
| `batch-size`     | Tamanho do batch                                     |
| `ubatch-size`    | Tamanho do micro-batch                               |
| `n-cpu-moe`      | Número de experts CPU para modelos MoE               |
| `min-p`          | Amostragem min-p (ex: 0.0)                           |
| `presence-penalty`| Penalidade de presença (ex: 0.0, 1.5)               |
| `repeat-penalty` | Penalidade de repetição (ex: 1.0)                    |
| `tools`          | Habilitar ferramentas (ex: `all`)                    |

### Modelos Disponíveis

| Seção                                   | Modelo                                                      | Contexto | Notas                                          |
|-----------------------------------------|-------------------------------------------------------------|----------|------------------------------------------------|
| `Gemma4_12B`                           | Gemma 4 12B IT (Q4_K_XL)                                   | 49152    | Multimodal (texto)                             |
| `Gemma4_12B_Hauhau`                    | Gemma 4 12B Uncensored Balanced (HauhauCS)                 | 49152    | Multimodal (texto, imagem, áudio)              |
| `Qwen3.6_28B_A3B`                      | Qwen 3.6 28B-A3B MoE (Q4_K_M)                              | 49152    | MoE (28 experts CPU)                           |
| `Qwen3.6_35B_General`                  | Qwen 3.6 35B-A3B Thinking General (Q4_K_M)                 | 49152    | MoE (24 experts CPU) / temp=1.0 / penalidades  |
| `Qwen3.6_35B_General_VL`               | Qwen 3.6 35B-A3B Thinking General VL (Q4_K_M)              | 49152    | MoE (24 experts CPU) / mmproj pendente         |
| `Qwen3.6_35B_Code`                     | Qwen 3.6 35B-A3B Thinking Code (Q4_K_M)                    | 49152    | MoE (24 experts CPU) / temp=0.6 / sem penalty  |
| `Qwen3.6_35B_It_General`               | Qwen 3.6 35B-A3B Instruct General (Q4_K_M)                 | 49152    | MoE (24 experts CPU) / temp=0.7 / top-p=0.8    |
| `Qwen3.6_35B_It_Reasoning`             | Qwen 3.6 35B-A3B Instruct Reasoning (Q4_K_M)               | 49152    | MoE (24 experts CPU) / temp=1.0                |
| `Ornith1.0_9B`                         | Ornith 1.0 9B (Q4_K_M)                                     | 65536    | Contexto expandido                             |
| `Ornith_1.0_35B`                       | Ornith 1.0 35B (Q4_K_M)                                    | 49152    | MoE (24 experts CPU) / temp=0.6 / min-p=0.0    |
| `Qwen3.6_35B_A3B_Hauhau_Aggressive`    | Qwen 3.6 35B Uncensored Aggressive (HauhauCS)              | 49152    | MoE (24 experts CPU) / multimodal              |
| `Bonsai-27B_Q1_0`                      | Bonsai 27B (Q1_0)                                          | 49152    | Multimodal (texto, imagem) / alta compressão   |

---

## API OpenAI-Compatible

### Endpoints

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| `/v1/models` | GET | Lista modelos disponíveis |
| `/v1/chat/completions` | POST | Geração de texto / chat |
| `/v1/embeddings` | POST | Embeddings |

### Exemplo de uso com curl

```bash
# Listar modelos
curl http://localhost:8081/v1/models

# Chat completion
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.6_35B_Code",
    "messages": [{"role": "user", "content": "Olá, como você está?"}],
    "temperature": 0.7
  }'
```

### Exemplo com Python (openai library)

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

## Fluxo de Trabalho

```bash
# Verificar status
docker compose ps

# Iniciar servidor
./manage.sh start

# Parar servidor
./manage.sh stop

# Ver logs
docker logs llama-cpp

# Testar API
curl http://localhost:8081/v1/models
```

---

## Trocar Modelo Ativo

O servidor suporta até `--models-max 1` — apenas um modelo carregado por vez. Para trocar:

```bash
# Parar o servidor
./manage.sh stop

# Iniciar com modelo diferente (via API do próprio llama-server)
# Ou mudar a ordem/parâmetros no models.ini
```

No llama.cpp, modelos são carregados/unloaded via API:

```bash
# Carregar um modelo específico
curl -X POST http://localhost:8081/v1/load_model \
  -H "Content-Type: application/json" \
  -d '{"model_alias": "Qwen3.6_35B_General"}'

# Unload modelo atual
curl -X POST http://localhost:8081/v1/unload_model
```

---

## OpenWA MCP — Integração com Open WebUI

### Configurar MCP no Open WebUI

Após iniciar o stack, configure o MCP no Open WebUI:

1. Acesse **http://localhost:8080**
2. Faça login como **administrador**
3. Vá em **⚙️ Admin Settings → External Tools**
4. Clique em **+ (Add Server)**
5. Configure:

| Campo | Valor |
|-------|-------|
| **Type** | `MCP (Streamable HTTP)` |
| **Server URL** | `http://localhost:2785/mcp` |
| **Auth** | `Bearer <API_KEY>` |

6. A **API Key** está em `openwa-data/.api-key` dentro do container:

```bash
docker exec openwa cat /app/data/.api-key
```

7. Clique em **Save** e reinicie o Open WebUI se solicitado.

> **⚠️ Importante**: Use o tipo **MCP (Streamable HTTP)**. Usar OpenAPI type causa crash na UI ou loading infinito.

### Testar MCP via curl

```bash
# Obter API key
API_KEY=$(docker exec openwa cat /app/data/.api-key)

# Testar endpoint MCP
curl -X POST http://localhost:2785/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

### Variáveis de Ambiente OpenWA

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `MCP_ENABLED` | `false` | Habilita o servidor MCP |
| `MCP_READONLY` | `true` | Modo read-only (false = expor ferramentas de escrita) |
| `MCP_RATE_LIMIT_MAX` | `60` | Máx de tool calls por key por janela |
| `MCP_RATE_LIMIT_WINDOW_MS` | `60000` | Tamanho da janela de rate limit (ms) |
| `MCP_IP_RATE_LIMIT_MAX` | `120` | Máx de requests por IP (pré-autenticação) |
| `MCP_IP_RATE_LIMIT_WINDOW_MS` | `60000` | Janela de rate limit por IP (ms) |
| `AUTO_START_SESSIONS` | `false` | Auto-reconectar sessões autenticadas no boot |
| `DATABASE_TYPE` | `sqlite` | sqlite ou postgres |
| `API_PORT` | `2785` | Porta host mapeada |

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
