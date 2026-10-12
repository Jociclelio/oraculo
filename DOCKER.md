# Docker — Stack Oraculo (Open WebUI + agentes; serving via llama-swap no host)

Stack Docker com **Open WebUI** (interface web), **Open Terminal** (substrato
de execução agêntica), **SearXNG** (busca web) e **OpenWa** (gateway WhatsApp
com MCP). O **serving de LLM saiu do compose**: o antigo serviço `llama-cpp`
foi substituído pelo **llama-swap**, um **processo de host** (fora do
`docker-compose.yml`) que sobe **containers Docker efêmeros por modelo**
sob demanda.

---

## Requisitos

- **Docker** e **Docker Compose** instalados
- **NVIDIA Container Toolkit** configurado (GPU NVIDIA)
- Mínimo **10 GB** de disco livre (por modelo)

## Variáveis de ambiente (`.env`)

O `docker-compose.yml` lê os segredos do `.env` na raiz do projeto (não versionado). Criar antes de subir:

```bash
cp .env.example .env   # ou criar manualmente
```

| Variável | Descrição |
|----------|-----------|
| `WEBUI_SECRET_KEY` | Chave secreta do Open WebUI (persistência OAuth/MCP) |
| `OPEN_TERMINAL_API_KEY` | Autenticação do open-terminal (gerar com `openssl rand -hex 32`) |

> O SearXNG usa `searxng/settings.yml` (local, gitignored) — copiar de `searxng/settings.example.yml` e definir um `secret_key` aleatório.

---

## Serviços (8 — sem `llama-cpp`)

> **Mudança de arquitetura (task 006 do plano llama-swap-multi-engine)**: o
> serviço `llama-cpp` e o mount do `models.ini` foram **removidos** do
> compose. O serving passou a ser o **llama-swap, processo de host** (seção
> abaixo). `docker compose config --services` → `open-webui`,
> `open-terminal`, `searxng`, `comfyui`, `mcp-playwright`, `mcp-memory`,
> `openwa`, `openwa-docker-proxy`.

### open-webui — Interface Web

- **Imagem**: `ghcr.io/open-webui/open-webui:main`
- **Container**: `open-webui`
- **Porta**: `8080` (rede host)
- **Volume**: `open-webui-data → /app/backend/data`
- **Dependência**: `searxng` (o serving llama-swap não é serviço do compose)
- **Rede**: `host`

Interface web para interagir com os modelos. Configurada para conectar ao proxy llama-swap via `http://localhost:8081/v1`.

**Variáveis de ambiente**:

| Variável | Valor | Descrição |
|----------|-------|-----------|
| `OAI_API_BASE` | `http://localhost:8081/v1` | URL da API do llama-swap (proxy único) |
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

Único container **do compose** com acesso ao Docker socket; o openwa o usa via `DOCKER_HOST=tcp://openwa-docker-proxy:2375`. (Os containers de modelo criados pelo llama-swap usam o socket diretamente pelo daemon, via CLI `docker` no host.)

### mcp-playwright — Playwright MCP (ferramenta de navegador)

- **Imagem**: `mcr.microsoft.com/playwright/mcp:v0.0.83` (pinado)
- **Container**: `mcp-playwright` (`network_mode: host`)
- **MCP Streamable HTTP**: `http://localhost:8931/mcp` (bind `127.0.0.1`)
- **`shm_size`**: 1 GiB (chromium estoura o `/dev/shm` padrão de 64 MiB)

O entrypoint da imagem já traz `--headless --browser chromium --no-sandbox`;
o `command` do compose só acrescenta `--port 8931 --host 127.0.0.1`. Usa rede
host de propósito: em bridge o `localhost` do container é o próprio container e
o navegador não alcança `:8080`/`:8081`/`:8888` (`ERR_CONNECTION_REFUSED`); com
rede host o bind tem de ser `127.0.0.1` para não expor o MCP na LAN. Serve para
o agente abrir URL, clicar, preencher formulário, ler SPA e tirar screenshot
(25 tools: `browser_navigate`, `browser_click`, `browser_snapshot`, …).

### mcp-memory — Grafo de conhecimento (stdio → HTTP)

- **Imagem**: `supercorp/supergateway:4.1.0` (pinado)
- **Container**: `mcp-memory` (`user: 1000:1000`)
- **Porta**: `127.0.0.1:8932`
- **MCP Streamable HTTP**: `http://localhost:8932/mcp`
- **Volumes**: `./mcp-data → /data` (o `memory.json`), `./mcp-data/npm-cache → /tmp/npm-cache`

`@modelcontextprotocol/server-memory` é **stdio-only**; o supergateway faz a
ponte stdio → Streamable HTTP (`--outputTransport streamableHttp --stateful
--sessionTimeout 300000`). O mesmo `mcp-data/memory.json` é usado pelo **memory
do opencode** (`MEMORY_FILE_PATH` em `~/.config/opencode/opencode.json`), ou
seja, um único grafo compartilhado entre os dois clientes.

> **Gotchas**: (1) montar o `memory.json` como **arquivo** quebra a gravação —
> o server faz rename atômico e recebe `EBUSY` sobre bind mount de arquivo
> único; monte o **diretório**. (2) rodando como root o arquivo ficava
> `root:root` e o opencode (uid 1000) não conseguia escrever — daí o
> `user: "1000:1000"` com cache do npm em diretório do próprio usuário.

### Conexões MCP do Open WebUI (`tool_server.connections`)

O Open WebUI fala MCP **somente via Streamable HTTP** (sem stdio nativo). As
conexões ficam na chave `tool_server.connections` do `webui.db` — **o banco tem
precedência sobre o env `TOOL_SERVER_CONNECTIONS`** depois da primeira
inicialização (mesma regra do `WEBSEARCH_ENGINE`). Registradas (admin-only,
`config.access_grants` vazio):

| id | URL | Origem |
|----|-----|--------|
| `openwa` | `http://localhost:2785/mcp` | compose (bearer) |
| `context7` | `https://mcp.context7.com/mcp` | SaaS (sem auth) |
| `playwright` | `http://localhost:8931/mcp` | compose |
| `memory` | `http://localhost:8932/mcp` | compose |

No chat, as tools entram pelo seletor de ferramentas (o request leva
`tool_ids: ["server:mcp:<id>"]`). Verificar de fora da UI, com o próprio
cliente do Open WebUI:

```bash
docker exec -i open-webui python - <<'PY'
import asyncio
from open_webui.utils.mcp.client import MCPClient
async def main():
    c = MCPClient(); await c.connect("http://localhost:8932/mcp")
    print([t["name"] for t in await c.list_tool_specs()])
asyncio.run(main())
PY
```

> O log de startup `Initialized 0 tool server(s)` **não** é erro: o
> pre-fetch só cobre conexões `openapi`; MCP é conectado sob demanda por
> `connect_mcp_server()` a cada request.

### comfyui — Geração/edição de imagens (Qwen-Image 2.1 Turbo)

- **Imagem**: `yanwk/comfyui-boot:cu126-slim-20261005` (pinada; ComfyUI
  v0.38.2 + ComfyUI-Manager, CUDA 12.6 / Python 3.12)
- **Container**: `comfyui` (`network_mode: host`) — UI/API em
  `http://localhost:8188` via gpu-shim; ComfyUI em `127.0.0.1:8189`
- **`gpus: all`** (o daemon já tem runtime nvidia default; ver `comando.txt`)
- **`CLI_ARGS=--disable-smart-memory`**: descarrega os pesos da VRAM para RAM
  ao fim de cada geração. Sem isso o ComfyUI retém ~4-6 GB e a próxima carga
  de LLM no llama-swap dá OOM. Custo: recarregar pesos da RAM na run seguinte
  (segundos, irrelevante no turbo de 8 passos).

**Modelos** (fonte da verdade: `models/comfyui/`, montado em
`/root/ComfyUI/models`; guia de instalação: `models/MODELS_INSTALL.md`):

| Papel | Arquivo | Tamanho |
|-------|---------|---------|
| Difusão | `diffusion_models/qwen_image_2.1_turbo_int8_convrot.safetensors` | 7,26 GB |
| Text encoder | `text_encoders/qwen3vl_8b_w4a8.safetensors` | 5,9 GB |
| VAE | `vae/qwen_image_2.1_vae_bf16.safetensors` | 645 MB |

O `int8_convrot` é nativo do ComfyUI (sem custom node) e mais rápido que
GGUF em Ampere — decisão validada: os GGUFs de difusão foram removidos
(`ComfyUI-GGUF` nem é instalado).

**Volumes**: `./models/comfyui → /root/ComfyUI/models`;
`./comfyui/{custom_nodes,input,output,user}` → idem no container; caches de
HF/torch em volumes nomeados (`comfyui-hf-cache`, `comfyui-torch-cache`).

- `./comfyui/user-scripts` → `/root/user-scripts`: `pre-start.sh` (sourced
  pelo entrypoint) sobe o gpu-shim; log em `comfyui/user/gpu-shim.log`.
- O entrypoint copia o bundle `/default-comfyui-bundle/ComfyUI` para
  `/root/ComfyUI` no primeiro boot com `--no-clobber` — os binds vazios são
  populados automaticamente (inclusive o Manager em `custom_nodes`).
- O núcleo do ComfyUI vive na camada gravável do container: persiste entre
  restarts, mas **recriar o container** volta ao snapshot da imagem (pip
  installs do usuário vão para `/root/.local`, mesmo comportamento).
- Saídas em `./comfyui/output/` (ignorado pelo git); workflows API versionados
  em `./comfyui/workflows/`.

**Templates da UI nativa** (override de template): os oficiais
`image_qwen_image_2_1_{t2i,image_edit}` foram adaptados à nossa stack
(turbo int8 + w4a8, 8 passos) e vivem versionados em
`comfyui/workflows/templates/`, instalados em
`comfyui/user/default/workflows/` (o frontend do ComfyUI checa esse
override antes do template embutido, que aponta para os modelos
não-turbo/int8 que não temos).

**Gotcha do shim**: o frontend pede userdata com `%2F` codificado
(`/api/userdata/workflows%2Ffoo.json`) e o backend decodifica — mas
`rel_url.path` do aiohttp já decodifica, o que quebrava a rota
(`/userdata/{file}` é de segmento único). O shim repassa
`request.raw_path` (percent-preserved) por isso. Sintoma do bug anterior:
override de template dava 404 e a UI nativa carregava o builtin com
modelos ausentes.

**Workflows API para o Open WebUI** (adaptados dos templates oficiais
`image_qwen_image_2_1_{t2i,image_edit}`; turbo = 8 passos, CFG 1, euler/simple):

| Workflow | Arquivo |
|----------|---------|
| Text-to-image | `comfyui/workflows/qwen_image_2_1_turbo_t2i_api.json` |
| Edição de imagem | `comfyui/workflows/qwen_image_2_1_turbo_edit_api.json` |

Grafo essencial (ambos): `UNETLoader` → `QwenImage21Cache` → `KSampler`;
`CLIPLoader (qwen_image)` + `VAELoader` → `TextEncodeQwenImage21`. No t2i o
latente vem de `EmptyLatentImage`; na edição vem da **saída 2 do encoder**
(a referência define o canvas). Slots de referência no API JSON usam a chave
`images.image_1` (não `image_1` — validação aceita ambas, a execução não).

**Configuração no Open WebUI** (gravada em `webui.db` — banco tem precedência
sobre env, regra 6; reconfigurável em Admin > Settings > Images):

| Chave | Valor |
|-------|-------|
| `image_generation.enable` / `engine` | `true` / `comfyui` |
| `image_generation.model` | `qwen_image_2.1_turbo_int8_convrot.safetensors` |
| `image_generation.size` / `steps` | `1024x1024` / `8` |
| `image_generation.comfyui.base_url` | `http://localhost:8188` |
| `image_generation.comfyui.workflow` + `.nodes` | t2i API JSON + mapeamento |
| `images.edit.enable` / `engine` | `true` / `comfyui` |
| `images.edit.comfyui.base_url` / `workflow` / `nodes` | mesmo server + edit API JSON |

Mapeamento de nós (`nodes`: `[{"type","node_ids","key"}]`; types: `model`,
`prompt`, `negative_prompt`, `image`, `width`, `height`, `n`, `steps`, `seed`):

| Parâmetro | t2i | edit |
|-----------|-----|------|
| prompt | `prompt` → nó 6 | `prompt` → nó 6 |
| model | `unet_name` → nó 1 | `unet_name` → nó 1 |
| width/height | → nó 5 (EmptyLatentImage) | — (canvas vem da referência) |
| steps/seed | → nó 7 (KSampler) | — |
| image | — | `image` → nós **5 e 10** (LoadImage; upload automático) |

**Múltiplas imagens na edição (10 slots)**: a tool `edit_image` do Open
WebUI aceita lista (`image_urls`), o router faz upload de todas e o
mapeamento distribui `image[i] → node_ids[i]` — `node_ids ["5","10".."18"]`
ligam os 10 slots do `TextEncodeQwenImage21` (`images.image_1`..`image_10`):
a 1ª imagem é a editada, as demais são referências endereçáveis no prompt
como `<image2>`..`<image10>` (o nó aceita 16; 10 é o que o template oficial
liga). Sem imagem num slot, o LoadImage correspondente carrega
`input/placeholder.png` (64×64, cinza).

**`resolution=0` no nó 6 é obrigatório com referências**: o parâmetro define
o orçamento de pixels para REDIMENSIONAR cada referência — com o default
1024, cada placeholder de 64×64 era ampliado para ~1024² e entrava com
~4k tokens na sequência do DiT (9 placeholders ≈ +36k tokens → OOM no
KSampler com CUDA a ~100 MiB livres). Com 0, cada referência entra no
tamanho próprio (o canvas vem do latente do encoder, ou seja, do tamanho
de image_1). Validado: 1 imagem + 9 placeholders sem degradação (42,5%
alterados, igual ao baseline) e composição com 3 imagens (99,6%).

**Referências grandes custam caro**: 10 fotos de 12 MP viram dezenas de
milhões de tokens de atenção — se uma edição de muitas referências der OOM
ou ficar lenta, é o tamanho delas, não o engine.

**VRAM COMPARTILHADA** (a mesma 3060 do llama-swap e do desktop) — a
liberação é bidirecional e automática, sem job em background:

- **DiT → LLM**: `CLI_ARGS=--disable-smart-memory` descarrega os pesos para
  RAM ao fim de cada geração; a VRAM cai para **~190 MiB** (só contexto
  CUDA). O próximo request de chat recarrega o LLM normalmente.
- **LLM → DiT**: o ComfyUI escuta em `127.0.0.1:8189` atrás do **gpu-shim**
  (`comfyui/user-scripts/gpu-shim.py`, sobe via `pre-start.sh` na porta
  canônica 8188). O shim repassa HTTP e WebSocket e, no caminho de geração
  (Open WebUI/API — requests sem `Origin` da UI nativa), avalia a VRAM
  livre via `nvidia-smi`: se < 8 GiB, chama `GET :8081/unload` do
  llama-swap (síncrono, ~0,5 s) e espera a VRAM estabilizar/aparecer antes
  de repassar. O teardown do processo do LLM pode levar dezenas de
  segundos — o shim aguenta isso (teto 45 s, encerra cedo se estável).
  O polling da UI nativa do ComfyUI **nunca** descarrega o LLM (gate por
  `Origin: …:8188`).
- Sem modelo LLM carregado, o shim não faz nada (VRAM livre > 8 GiB). Com
  jogos no desktop (ex.: CS2 ~2,2 GB), a geração ainda cabe (medido).
- `./manage.sh unload` usa o mesmo endpoint `GET /unload` para liberação
  manual (fallback `docker rm -f` se o llama-swap estiver fora).
- O "aborted" no log do llama-swap durante carga de modelo é esperado se
  algo chamar `/unload` no meio de um health check — o gate por VRAM evita
  isso no fluxo normal.


---

## Serving fora do compose — llama-swap (processo de host)

O llama-swap é um binário em `bin/llama-swap` (instalado por
`./llama-swap/install.sh`), iniciado por `./manage.sh start` com
`-listen 127.0.0.1:8081 -config llama-swap/config.yaml`. Para cada modelo
requerido ele executa o `cmd` da entry (um `docker run --rm --name
ls-<Modelo> ...`), aguarda o health check e roteia a API; ao trocar de
modelo, o container anterior é encerrado (`cmdStop: docker rm -f
ls-<Modelo>`) — **só 1 modelo carregado por vez**, descarregado também após
`ttl: 300` s ocioso.

- **Engines**: imagem stock `ghcr.io/ggml-org/llama.cpp:full-cuda` (macro
  `docker-stock`), imagem local do fork PrismML `llama.cpp-prismml:latest`
  para os Bonsai (build em `engines/llama.cpp-prismml/`, commit pinado
  `84445367f` — **nunca stock** para Bonsai) e Strata (entry comentada,
  infra em `strata/`).
- **Monte**: os containers de modelo montam `./models:/models` (mesmo monte
  do antigo serviço); o `models.ini` não é mais montado em lugar nenhum —
  os parâmetros vivem em `llama-swap/config.yaml`.
- **Portas**: os containers publicam apenas no loopback (`127.0.0.1:${PORT}`,
  tipicamente `:58xx`); o único ponto de entrada é o proxy em `:8081`.
- **Posicionamento**: stack para **1 usuário por vez** (`-np 1` default;
  `np>1` só como exceção comentada no config).

Detalhes de entries/parâmetros: [`llama-swap/config.yaml`](llama-swap/config.yaml) e seção llama-swap do [`AGENTS.md`](AGENTS.md).

### Redes

```
┌─────────────────────────────────────────────────────────────────┐
│  Host                                                            │
│   llama-swap (proxy, 127.0.0.1:8081) — processo de host          │
│   open-webui (8080, network_mode: host)                          │
│   containers efêmeros ls-<Modelo> (127.0.0.1:58xx→8080)          │
│     ↑ criados/destruídos pelo llama-swap (fora do compose)       │
│   searxng (8888) · open-terminal (8000) — bridge, só localhost   │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  openwa-network      ←→  openwa + openwa-docker-proxy            │
│  openwa-internal-docker (internal: true, sem saída externa)      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Gerenciamento

### Docker Compose (serviços auxiliares)

```bash
# Iniciar todos os serviços do compose
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

### Script de gerenciamento (llama-swap — serving)

```bash
./manage.sh start     # inicia o llama-swap em background (pidfile + logs/llama-swap.log)
./manage.sh stop      # encerra via pidfile (SIGTERM → SIGKILL)
./manage.sh restart   # para e inicia de novo
./manage.sh status    # mostra se está rodando
```

---

## API OpenAI-Compatible

A API é exposta pelo proxy llama-swap em `127.0.0.1:8081`; o roteamento para
o container do modelo é transparente para o cliente.

### Endpoints

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| `/v1/models` | GET | Lista as entries configuradas no `llama-swap/config.yaml` |
| `/v1/chat/completions` | POST | Chat / geração de texto (carrega/swap o modelo solicitado) |
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

## Gerenciar Modelos

O llama-swap mantém **1 modelo carregado por vez** (como o antigo
`--models-max 1`), mas o swap é **automático por request**: pedir outro
`model` descarrega o anterior e sobe o novo. Não existem mais os endpoints
`load_model`/`unload_model` do serviço antigo, nem `models.ini` para editar —
os parâmetros de cada modelo vivem em [`llama-swap/config.yaml`](llama-swap/config.yaml)
(entries `cmd`/`cmdStop`/`ttl`).

Para adicionar um modelo novo: baixar o GGUF (guia em
[`models/MODELS_INSTALL.md`](models/MODELS_INSTALL.md)), criar a entry no
config e `./manage.sh restart`.

---

## Open WebUI

Acessar a interface web em **http://localhost:8080**.

Primeiro acesso: criar conta de administrador. O Open WebUI já vem configurado para conectar ao proxy llama-swap automaticamente.

Para adicionar outros backends de API, ir em **Settings → Connections → OpenAI API** e configurar:

| Campo | Valor |
|-------|-------|
| API Base URL | `http://localhost:8081/v1` |
| API Key | `llama-cpp-local` |

---

## Estrutura de Dados

```
oraculo/
├── models/                   # Modelos GGUF (montados nos containers efêmeros)
│   ├── .../
│   ├── models.ini            # HISTÓRICO (desativado) — parâmetros migraram p/ config.yaml
│   └── MODELS_INSTALL.md     # Guia de instalação de modelos
│
├── llama-swap/
│   ├── install.sh            # instala o binário de release em bin/
│   └── config.yaml           # entries dos modelos (fonte da verdade)
├── bin/llama-swap            # binário (gitignored)
├── logs/                     # llama-swap.log + pidfile (gitignored)
├── engines/llama.cpp-prismml/# engine Docker dedicada do fork PrismML (Bonsai)
├── strata/                   # infra Strata (Dockerfile + README; modelo não baixado)
│
├── searxng/
│   └── settings.yml          # Config do SearXNG (formats json p/ Open WebUI)
│
├── docker-compose.yml        # Serviços auxiliares (sem llama-cpp)
├── manage.sh                 # Script de gerenciamento do llama-swap
├── .env                      # Variáveis de ambiente
├── DOCKER.md                 # Documentação Docker
└── README.md                 # Guia rápido de uso
```

---

## Backup

```bash
# Backup da config de serving (entries/parâmetros)
tar -czf llama-swap-config-backup.tar.gz llama-swap/config.yaml

# Backup do Open WebUI
docker exec open-webui tar -czf /tmp/openwebui-backup.tar.gz /app/backend/data

# Restaurar
tar -xzf llama-swap-config-backup.tar.gz
```

---

## Troubleshooting

### GPU não é reconhecida

```bash
# Verificar NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi

# Verificar se o container do modelo em curso tem acesso à GPU
docker inspect ls-<Modelo> | grep -A5 GPU
```

### Modelo não carrega

```bash
# Verificar se o arquivo .gguf existe em models/ (montado em /models)
ls -la models/<dir-do-modelo>/

# Ver o log do proxy (swap, health checks, erros de carga)
tail -n 50 logs/llama-swap.log

# Ver o log do container do modelo (enquanto Up)
docker logs ls-<Modelo>
```

### Falha intermitente `exit 125` na primeira carga após restart

Flake **recorrente** documentado na validação e2e (task 007 do plano
llama-swap-multi-engine): após `./manage.sh start`, a primeira carga de um
modelo falha às vezes com `upstream command exited prematurely` (o
`docker run` do llama-swap sai com `code=125`); visto entre sessões em
`Ornith1.5_9B_MTP`, `bonsai-27b` e `Gemma4_12B`. Em parte das ocorrências o
retry/health-check seguinte recupera sozinho; nas demais, o sucesso só vem em
sessão posterior. **Causa indeterminada** — a hipótese de container órfão
(conflito de nome `ls-<Modelo>`) foi enfraquecida pelo log: o start já roda
`docker rm -f ls-<Modelo>` antes do `docker run` e mesmo assim houve
`exit 125`. Workaround: repetir o request ou `./manage.sh restart`; se
houver container órfão manual, `docker rm -f ls-<Modelo>`. Ao reproduzir,
capturar stderr do `docker run` / `docker events` (follow-up do plano).

### Storage cheio

```bash
# Verificar uso
du -sh models/*/

# Limpar modelos não usados
rm -rf models/NOME_DO_MODELO/
```

### Logs

```bash
# Logs do proxy llama-swap (e dos modelos: cada container efêmero)
tail -f logs/llama-swap.log
docker logs ls-<Modelo>

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

### Open WebUI não conecta ao llama-swap

```bash
# Verificar se o proxy está rodando (processo de host, não do compose)
./manage.sh status

# Verificar se a API está respondendo
curl http://localhost:8081/v1/models

# Verificar conexão do open-webui para o proxy
docker exec open-webui curl -s http://localhost:8081/v1/models

# Reiniciar o open-webui
docker restart open-webui
```
