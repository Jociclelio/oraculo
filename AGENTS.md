# oraculo

Servidor local de LLMs com **llama.cpp** (inferência GPU) e interface **Open WebUI**. Expondo:

- **API OpenAI-compatible** (llama.cpp) → porta `8081`
- **Open WebUI** → porta `8080`
- **Open Terminal** (execução agêntica) → porta `8000`
- **SearXNG** (busca web privada) → porta `8888`
- **OpenWa** (gateway WhatsApp + MCP) → porta `2785`

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
├── docker-compose.yml          # Definição dos serviços Docker
├── manage.sh                   # Script de gerenciamento (llama-cpp)
├── .env                        # Variáveis de ambiente
│
├── searxng/
│   └── settings.yml            # Config do SearXNG (formats json p/ Open WebUI)
│
├── models/
│   ├── models.ini              # Configurações dos modelos para o servidor llama.cpp
│   ├── MODELS_INSTALL.md       # Guia de instalação de modelos
│   └── .../
│
├── DOCKER.md                   # Documentação Docker detalhada
└── README.md                   # Guia rápido de uso
```

---

## docker-compose.yml

Define **cinco serviços**: llama-cpp (inferência GPU), open-webui (interface web), open-terminal (execução agêntica), searxng (busca web) e openwa + openwa-docker-proxy (WhatsApp/MCP):

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
| **Env**       | `OAI_API_BASE`, `WEBSEARCH_ENGINE`, `SEARXNG_QUERY_URL`, `TERMINAL_SERVER_CONNECTIONS` |

Interface web para interagir com os LLMs via navegador. Configurada para conectar ao llama-cpp automaticamente.

| Variável                  | Valor                                        | Descrição                                  |
|---------------------------|----------------------------------------------|--------------------------------------------|
| `OAI_API_BASE`            | `http://localhost:8081/v1`                   | API do llama.cpp                           |
| `WEBUI_SECRET_KEY`        | (gerado)                                     | Persistência de tokens OAuth/MCP           |
| `WEBSEARCH_ENGINE`        | `searxng`                                    | Motor de busca web nativo                  |
| `SEARXNG_QUERY_URL`       | `http://localhost:8888/search?q=<query>`     | Endpoint do SearXNG                        |
| `TERMINAL_SERVER_CONNECTIONS` | (JSON) `oraculo-terminal` @ `:8000`      | Conexão pré-configurada com o Open Terminal |

> **Importante**: `WEBUI_SECRET_KEY` é obrigatório em setups Docker. Sem ele, ferramentas MCP conectadas via OAuth não persistem tokens entre reinicializações.

> ⚠️ **ConfigVar**: `WEBSEARCH_ENGINE`, `SEARXNG_QUERY_URL` e `TERMINAL_SERVER_CONNECTIONS` são persistidos no `webui.db` na primeira inicialização — após isso, o **banco tem precedência sobre o env**. Para alterar: UI admin ou edição direta do `webui.db`.

### Serviço `open-terminal` — Execução Agêntica

| Item          | Valor                                              |
|---------------|-----------------------------------------------------|
| **Imagem**    | `ghcr.io/open-webui/open-terminal`                |
| **Container** | `open-terminal`                                    |
| **Porta**     | `127.0.0.1:8000` (somente localhost)               |
| **Volumes**   | `open-terminal-data → /home/user`                  |
| **Env**       | `OPEN_TERMINAL_API_KEY`                            |

Substrato de execução (shell, filesystem, código) para o agente do Open WebUI. Conexão pré-configurada como **"Oraculo Terminal"**. Requer modelo com **Function Calling = Native**.

### Serviço `searxng` — Busca Web

| Item          | Valor                                              |
|---------------|-----------------------------------------------------|
| **Imagem**    | `searxng/searxng`                                  |
| **Container** | `searxng`                                          |
| **Porta**     | `127.0.0.1:8888` (somente localhost)               |
| **Volumes**   | `./searxng/settings.yml → /etc/searxng/settings.yml` |

Metabuscador privado usado como motor de busca web do Open WebUI. O `settings.yml` habilita `formats: [html, json]` — **o JSON é obrigatório** para a integração.

### Serviços `openwa` + `openwa-docker-proxy` — WhatsApp/MCP

| Item          | openwa                                             | openwa-docker-proxy                        |
|---------------|-----------------------------------------------------|--------------------------------------------|
| **Imagem**    | `ghcr.io/rmyndharis/openwa:main`                  | `tecnativa/docker-socket-proxy:v0.4.2`     |
| **Porta**     | `127.0.0.1:2785`                                   | — (rede interna)                           |
| **Volumes**   | `openwa-data`, `openwa-sessions`                   | Docker socket (read-only, ops mínimas)     |
| **Redes**     | `openwa-network`, `openwa-internal`                | `openwa-network`, `openwa-internal`        |

Gateway WhatsApp com MCP Streamable HTTP em `http://localhost:2785/mcp`. Autenticação via `X-API-Key`/`Bearer` — key gerada na primeira inicialização, salva em `openwa-data/.api-key`. O proxy é o único container com acesso ao Docker socket.

> O openwa também está conectado ao Open WebUI como **tool server MCP** (persistido em `tool_server.connections` no `webui.db`).



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
| `jinja`          | `1`     | Usa template Jinja para chats                |
| `threads`        | `5`     | Número de threads CPU                        |
| `cache-ram`      | `2048`  | Cache RAM em MiB para modelos não carregados |
| `sleep-idle-seconds` | `300` | Descarrega modelo ocioso após 5 min        |

### Seções de Modelos

Cada seção `[Nome]` configura um modelo específico com os parâmetros override:

| Parâmetro        | Descrição                                            |
|------------------|------------------------------------------------------|
| `model`          | Caminho ao arquivo `.gguf` do modelo                 |
| `mmproj`         | Arquivo mmproj para multimodal (vision)              |
| `model-draft`    | Modelo draft para MTP (Multi-Token Prediction)       |
| `spec-type`      | Tipo de speculative decoding (ex: `draft-mtp`)       |
| `spec-draft-n-max` | Máximo de tokens draftados por passo               |
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
| `Gemma4_12B_MTP`                       | Gemma 4 12B IT (Q4_K_XL) + drafter MTP                     | 64000    | MTP speculative decoding / cache split q8_0 (target) + f16 (draft); máx. validado 196608 |
| `Gemma4_12B_Hauhau`                    | Gemma 4 12B Uncensored Balanced (HauhauCS)                 | 49152    | Multimodal (texto, imagem, áudio)              |
| `Qwen3.6_28B_A3B`                      | Qwen 3.6 28B-A3B MoE (Q4_K_M)                              | 49152    | MoE (28 experts CPU)                           |
| `Qwen3.6_35B_General`                  | Qwen 3.6 35B-A3B Thinking General (Q4_K_M)                 | 98304    | MoE (32 experts CPU) / temp=1.0 / penalidades  |
| `Qwen3.6_35B_General_VL`               | Qwen 3.6 35B-A3B Thinking General VL (Q4_K_M)              | 49152    | MoE (28 experts CPU) / mmproj pendente         |
| `Qwen3.6_35B_Code`                     | Qwen 3.6 35B-A3B Thinking Code (Q4_K_M)                    | 49152    | MoE (28 experts CPU) / temp=0.6 / sem penalty  |
| `Qwen3.6_35B_It_General`               | Qwen 3.6 35B-A3B Instruct General (Q4_K_M)                 | 98304    | MoE (32 experts CPU) / temp=0.7 / top-p=0.8    |
| `Qwen3.6_35B_It_Reasoning`             | Qwen 3.6 35B-A3B Instruct Reasoning (Q4_K_M)               | 98304    | MoE (32 experts CPU) / temp=1.0                |
| `Ornith1.5_9B_MTP`                      | Ornith 1.5 9B MTP (Q4_K_M, protoLabsAI)                    | 65536    | MTP speculative decoding / acceptance ~0.40   |
| `Ornith1.5_9B_DFlash`                   | Ornith 1.5 9B (Q4_K_M) + DFlash draft (audreyt)           | 65536    | DFlash speculative decoding / acceptance ~0.42 |
| `Ornith1.5_35B_MTP`                     | Ornith 1.5 35B-A3B MTP (APEX Compact, mudler)              | 49152    | MoE (28 experts CPU) / MTP / acceptance ~0.80 |
| `Qwen3.6_35B_A3B_Hauhau_Aggressive`    | Qwen 3.6 35B Uncensored Aggressive (HauhauCS)              | 98304    | MoE (32 experts CPU) / multimodal              |
| `PE_T2I_Heretic`                       | PE Heretic t2i (Q4_K_M)                                    | 16384    | Text-to-image / alias `pe-t2i`                 |
| `PE_I2I_Heretic`                       | PE Heretic i2i (Q4_K_M) + mmproj                           | 16384    | Image-to-image (visão) / alias `pe-i2i`        |

### Presets Ornith 1.5

Os modelos GGUF oficiais do Ornith 1.5 foram baixados em quantização Q4_K_M: 9B (5.78 GB) e 35B-A3B (21.71 GB). O preset 9B mantém contexto de 65.536 tokens; o 35B-A3B usa contexto de 49.152 tokens e configuração MoE com `n-cpu-moe = 28`. O `mmproj` não foi instalado.

### Preset `Gemma4_12B_MTP` — MTP Speculative Decoding

Configura o **Gemma 4 12B IT** com um **drafter MTP** (`mtp-gemma-4-12B-it.gguf`) para speculative decoding por multi-token prediction. Em RTX 3060 12GB alcança **contexto de 196.608 tokens (192K)** a ~**100 tok/s** (~72-85% de aceitação de draft), com 100% na GPU (zero CPU offload).

> ⚠️ **Sobre o contexto de 262.144 (256K)**: a config original do post X (ctx=262144) **falha OOM nesta máquina** porque Hyprland/Wayland ocupa ~880 MiB de VRAM da GPU (compartilhada com o display). O máximo validado nesta GPU+sw é **196.608** (192K), que deixa ~100 MiB de folga. Para atingir 256K seria preciso liberar a VRAM do display (GPU dedicada só para display, ou console/tty) ou usar uma GPU com mais VRAM.

** Truque de VRAM — split do KV cache:**

| Cache          | Tipo   | Motivo                                                           |
|----------------|--------|------------------------------------------------------------------|
| Target (K/V)   | `q8_0` | Herdado do `[*]` global; economiza VRAM no contexto longo (192K) |
| Draft  (K/V)   | `f16`  | Quantizar o cache do draft derruba a taxa de aceitação; f16 mantém ~70-85% de aceitação |

Parametros relevantes do preset:

| Parâmetro              | Valor  | Descrição                                              |
|------------------------|--------|--------------------------------------------------------|
| `model`                | Gemma 4 12B IT (Q4_K_XL) | Modelo alvo                         |
| `model-draft`          | `mtp-gemma-4-12B-it.gguf` | Drafter MTP                      |
| `spec-type`            | `draft-mtp` | Tipo de speculative decoding                    |
| `spec-draft-n-max`     | `4`    | Máximo de tokens draftados por passo                     |
| `ctx-size`             | `64000` | Contexto atual no `models.ini` (máx. validado nesta GPU: 196608/192K; ver nota acima) |
| `ngl`                  | `all`  | Todas as camadas do target na GPU                       |
| `spec-draft-ngl`      | `99`   | Todas as camadas do draft na GPU                        |
| `cache-type-k-draft`  | `f16`  | Cache K do draft em f16 (preserva aceitação)            |
| `cache-type-v-draft`  | `f16`  | Cache V do draft em f16 (preserva aceitação)            |
| `cache-ram`            | `0` (local) | Override do global `2048`; cache todo na GPU, conforme o post |
| `batch-size`           | `4096` | Batch lógico                                          |
| `ubatch-size`          | `1280` | Micro-batch pequeno -> reduz pico de VRAM no prompt proc |
| `temp` / `top-p` / `top-k` | `1.0` / `0.95` / `64` | Amostragem (mesma do comando base) |

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
