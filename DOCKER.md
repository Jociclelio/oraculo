# Docker — Stack Oraculo (llama-cpp + Open WebUI + agentes)

Stack Docker com **llama.cpp** (inferência GPU), **Open WebUI** (interface web), **Open Terminal** (substrato de execução agêntica), **SearXNG** (busca web) e **OpenWa** (gateway WhatsApp com MCP).

---

## Requisitos

- **Docker** e **Docker Compose** instalados
- **NVIDIA Container Toolkit** configurado (GPU NVIDIA)
- Mínimo **10 GB** de disco livre (por modelo)

---

## Serviços

### llama-cpp — Inferência GPU

- **Imagem**: `ghcr.io/ggml-org/llama.cpp:full-cuda`
- **Container**: `llama-cpp`
- **Porta**: `8081`
- **GPU**: 1× NVIDIA GPU (via env vars `NVIDIA_VISIBLE_DEVICES=all` + `NVIDIA_DRIVER_CAPABILITIES=compute,utility`, usando o runtime `nvidia` padrão do daemon)
- **Volume**: `./models → /models` (modelos GGUF)
- **Config**: `./models/models.ini → /app/models.ini`

Serve uma **API OpenAI-compatible** para geração de texto, chat e embeddings.

> **Importante**: Não usar o bloco `deploy.resources.reservations.devices` (equivalente a `--gpus`) neste serviço. Quando o daemon usa o runtime `nvidia` como padrão, o `--gpus` injeta a capability `graphics`, que tenta montar `libnvidia-gtk3.so.<versão>` no container. Se o host não tiver essa biblioteca (ex.: driver atualizado sem o pacote GTK correspondente), o container falha ao iniciar com `failed to fulfil mount request: open /usr/lib/libnvidia-gtk3.so...`. A configuração via env vars evita esse problema e expõe apenas `compute` (inferência) + `utility` (nvidia-smi).

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
| `WEBSEARCH_ENGINE` | `searxng` | Motor de busca web nativo (usa o SearXNG) |
| `SEARXNG_QUERY_URL` | `http://localhost:8888/search?q=<query>` | Endpoint de busca do SearXNG |

> **Importante**: `WEBUI_SECRET_KEY` é obrigatório em Docker. Sem ele, ferramentas MCP conectadas via OAuth perdem tokens entre reinicializações.

### open-terminal — Substrato de execução agêntica

- **Imagem**: `ghcr.io/open-webui/open-terminal`
- **Container**: `open-terminal`
- **Porta**: `127.0.0.1:8000` (somente localhost)
- **Volume**: `open-terminal-data → /home/user` (workspace persistente do agente)

Transforma o Open WebUI em um *agent harness*: o modelo pode executar comandos, criar/editar arquivos, rodar código e iniciar servidores dentro do container (isolado do host).

**Conexão com o Open WebUI** (pré-configurada):

A conexão é registrada automaticamente via `TERMINAL_SERVER_CONNECTIONS` no env do open-webui e persistida no banco. Aparece como **"Oraculo Terminal"** em *Settings → Admin → Integrations → Open Terminal*.

1. No chat, selecionar o terminal pelo ícone de nuvem (☁) no input
2. Se precisar recriar manualmente: URL `http://localhost:8000`, API Key = valor de `OPEN_TERMINAL_API_KEY`, Auth Type `Bearer`

> ⚠️ Essas variáveis são `ConfigVar`: o valor persistido no banco (volume) tem precedência sobre o env após a primeira inicialização. Para mudar a conexão, use a UI admin ou edite `terminal_server.connections` no `webui.db`.

> O modelo precisa ter **Function Calling = Native** (padrão desde v0.10.0) em *Workspace → Models*.

### searxng — Metabuscador

- **Imagem**: `searxng/searxng`
- **Container**: `searxng`
- **Porta**: `127.0.0.1:8888` (somente localhost)
- **Config**: `./searxng/settings.yml → /etc/searxng/settings.yml`

Metabuscador privado (agrega Google, Bing, DuckDuckGo etc. sem rastreamento). O Open WebUI o usa como motor de busca web nativo via `WEBSEARCH_ENGINE=searxng`. O `settings.yml` habilita `formats: [html, json]` — **o JSON é obrigatório** para a integração.

Teste manual:

```bash
curl "http://localhost:8888/search?q=teste&format=json"
```

### openwa — Gateway WhatsApp (MCP)

- **Imagem**: `ghcr.io/rmyndharis/openwa:main`
- **Container**: `openwa`
- **Porta**: `127.0.0.1:2785`
- **MCP Streamable HTTP**: `POST http://localhost:2785/mcp`
- **Auth**: header `X-API-Key` ou `Authorization: Bearer <key>` — a key é gerada na primeira inicialização e salva em `openwa-data/.api-key`
- **Volumes**: `openwa-data → /app/data`, `openwa-sessions → /app/data/sessions`

Gateway WhatsApp com MCP habilitado. Sessões não iniciam automaticamente (`AUTO_START_SESSIONS=false`).

### openwa-docker-proxy — Proxy do Docker socket

- **Imagem**: `tecnativa/docker-socket-proxy:v0.4.2`
- **Container**: `openwa-docker-proxy`
- **Acesso**: somente leitura ao Docker socket, com operações mínimas liberadas (`CONTAINERS`, `IMAGES`, `VOLUMES`, `INFO`, `PING`, `POST`, `DELETE`)

Único container com acesso ao Docker socket; o openwa o usa via `DOCKER_HOST=tcp://openwa-docker-proxy:2375`.

### Redes

```
┌─────────────────────────────────────────────────────────────┐
│                    Host Network                              │
│  llama-cpp (8081) ←→ open-webui (8080) ←→ searxng (8888)    │
│  open-terminal (8000) — bridge, só localhost                 │
│  (llama-cpp, open-webui: network_mode: host)                 │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  openwa-network      ←→  openwa + openwa-docker-proxy        │
│  openwa-internal-docker (internal: true, sem saída externa)  │
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
docker compose restart open-webui
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
│   ├── .../
│   ├── models.ini            # Configuração dos modelos do llama.cpp
│   └── MODELS_INSTALL.md     # Guia de instalação de modelos
│
├── searxng/
│   └── settings.yml          # Config do SearXNG (formats json p/ Open WebUI)
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


```

### Busca web não funciona no Open WebUI

```bash
# Verificar se o SearXNG responde com JSON
curl "http://localhost:8888/search?q=teste&format=json"

# Se der 403, conferir se settings.yml tem formats: [html, json]
cat searxng/settings.yml
```

### Open Terminal não conecta

```bash
# Verificar se está rodando
docker compose ps open-terminal

# Testar health
docker exec open-webui curl -s http://localhost:8000/health

# Ver a API key (se esqueceu)
docker logs open-terminal | grep -i "api key"
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


