# oraculo

Servidor local de LLMs com **llama-swap** (proxy multi-engine sobre
containers efêmeros de **llama.cpp** em GPU) e interface **Open WebUI**.
Expondo:

- **API OpenAI-compatible** (proxy llama-swap) → porta `8081`
- **Open WebUI** → porta `8080`
- **Open Terminal** (execução agêntica) → porta `8000`
- **SearXNG** (busca web privada) → porta `8888`
- **OpenWa** (gateway WhatsApp + MCP) → porta `2785`

---

## Documentação do Repositório

**Qualquer mudança no repositório deve ser descrita e atualizada nos arquivos de documentação correspondentes.**

- Alterações no `docker-compose.yml` → atualizar `DOCKER.md`
- Alterações no `llama-swap/config.yaml` ou modelos → atualizar `AGENTS.md`
- Alterações no `manage.sh` ou fluxo de uso → atualizar `README.md`
- Novos requisitos de hardware/software → atualizar `README.md`

Mantenha a documentação sincronizada com o código. Documentação desatualizada gera confusão e perda de conhecimento.

---

## Estrutura do Repositório

```
oraculo/
├── docker-compose.yml          # Serviços auxiliares (sem o antigo llama-cpp)
├── manage.sh                   # Gerenciamento do llama-swap (start|stop|restart|status)
├── .env                        # Variáveis de ambiente
│
├── bin/llama-swap              # Binário do proxy (release; gitignored)
├── logs/                       # llama-swap.log + pidfile (gitignored)
├── llama-swap/
│   ├── install.sh              # Instala a última release em bin/
│   └── config.yaml             # Entries dos modelos — FONTE DA VERDADE dos parâmetros
│
├── engines/llama.cpp-prismml/  # Engine Docker dedicada do fork PrismML (Bonsai 2)
│   ├── Dockerfile              # clone do branch `prism` em commit pinado + build CUDA sm_86
│   └── build.sh
│
├── strata/                     # Infra Strata/Qwen3.8-Flash-Next (entry comentada no config)
│   ├── Dockerfile
│   ├── build-engine.py
│   └── README.md               # Passos de instalação futura do modelo (~58 GB)
│
├── searxng/
│   └── settings.yml            # Config do SearXNG (formats json p/ Open WebUI)
│
├── models/
│   ├── models.ini              # HISTÓRICO (desativado) — parâmetros migraram p/ config.yaml
│   ├── MODELS_INSTALL.md       # Guia de instalação de modelos
│   └── .../
│
├── DOCKER.md                   # Documentação Docker detalhada
└── README.md                   # Guia rápido de uso
```

---

## llama-swap — serving multi-engine (processo de host)

O serving não é mais o container fixo `llama-cpp` do compose: é o
**[llama-swap](https://github.com/mostlygeek/llama-swap)** rodando no host,
subindo **um container Docker efêmero por modelo** sob demanda.

| Item            | Valor                                                            |
|-----------------|------------------------------------------------------------------|
| **Binário**     | `bin/llama-swap` (release v263; instalar com `./llama-swap/install.sh`) |
| **Escuta**      | `127.0.0.1:8081` (flag `-listen`; WebUI inalterada)              |
| **Config**      | `llama-swap/config.yaml` — macros `docker-stock`/`docker-prismml` + 17 entries |
| **Swap**        | 1 modelo carregado por vez; pedir outro descarrega o anterior (`cmdStop: docker rm -f ls-<Modelo>`) |
| **TTL**         | `ttl: 300` por entry — descarrega após 5 min ocioso (substitui o `sleep-idle-seconds` do models.ini) |
| **healthCheckTimeout** | `300` s — cobre carga a frio de GGUFs MoE de ~21 GB do NVMe |
| **Containers**  | `--rm`, nome fixo `ls-<Modelo>`, porta pública só loopback `127.0.0.1:${PORT}` (tipicamente `:58xx`) |
| **Monte**       | `./models:/models` (mesmo do antigo serviço)                      |
| **Log/pidfile** | `logs/llama-swap.log`, `logs/llama-swap.pid`                      |

> **Posicionamento (plano llama-swap-multi-engine)**: stack para **1 usuário
> por vez**. Todas as entries usam `-np 1`; `np>1` só como exceção pontual
> para modelos pequenos (exemplo comentado no fim do config.yaml). Meta de
> prefill/decode razoável com **contexto ≥ 64k** (128k quando VRAM e prefill
> permitirem).

### Engines

| Engine | Imagem | Entradas |
|--------|--------|----------|
| **stock** | `ghcr.io/ggml-org/llama.cpp:full-cuda` (macro `docker-stock`, `--entrypoint /app/llama-server`) | 15 entries clássicas (Gemma/Qwen/Ornith/PE) |
| **PrismML (fork)** | `llama.cpp-prismml:latest` — build local via `engines/llama.cpp-prismml/build.sh` (macro `docker-prismml`, `--entrypoint /usr/local/bin/llama-server`) | `bonsai-27b`, `bonsai-27b-pq2_0` |
| **Strata** | `strata:latest` (infra em `strata/`) | entry **comentada** — modelo não baixado |

### Engine Bonsai dedicada — regra **nunca stock**

Os GGUFs **Bonsai 2** (ternários PTQ1_0/PQ2_0) exigem o fork
**PrismML-Eng/llama.cpp** (branch `prism`): kernels ternários + Hadamard em
runtime são **exclusivos do fork**. A imagem stock **recusa** PTQ1_0/PQ2_0 ou
carrega como `Q2_0` legacy gerando lixo — por isso a engine é uma imagem
Docker dedicada construída no repo (`engines/llama.cpp-prismml/`), com o
fork **pinado** no commit `84445367f`
(`84445367fbaf79c00ff64bc93a0689cdb3eee54d`; o build falha se HEAD ≠ pin).
Confirmado em runtime: `system_fingerprint: "b1-8444536"` nos responses do
Bonsai. **Nunca** servir Bonsai com a imagem stock.

### Strata (Qwen3.8-Flash-Next) — infra preparada, entry desabilitada

`strata/` contém Dockerfile (upstream pinado), `build-engine.py` e
`README.md` com os passos de instalação futura. O modelo **não foi baixado**
(~58 GB na variante Coder IQ1_M; RAM 31 GB → única variante que cabe nos
32 GB da máquina). A entry `Strata:` permanece **comentada** no
`llama-swap/config.yaml` (`MODEL=IQ1_M`, `FAMILY=coder`, `CONTEXT=65536`);
para ativar: seguir `strata/README.md` e descomentar.

---

## docker-compose.yml

Define **cinco serviços**: open-webui (interface web), open-terminal
(execução agêntica), searxng (busca web) e openwa + openwa-docker-proxy
(WhatsApp/MCP). O antigo serviço `llama-cpp` (e o mount do `models.ini`)
foram **removidos** — o serving passou a ser o llama-swap, processo de host
fora do compose:

> **Decisão de design — hardware compartilhado**: a GPU é a mesma da máquina de uso pessoal. O stack é **request-driven** (modelo carrega sob demanda, descarrega após 5 min ocioso — `ttl: 300` do llama-swap) e **deliberadamente não-autônomo** — sem agentes/workflows em background que possam requerer VRAM sem supervisão. Ver seção "Decisões de Projeto" no `README.md`.

### Serviço `open-webui` — Interface Web

| Item          | Valor                                              |
|---------------|-----------------------------------------------------|
| **Imagem**    | `ghcr.io/open-webui/open-webui:main`              |
| **Container** | `open-webui`                                       |
| **Porta**     | `8080` (network_mode: host)                        |
| **Rede**      | `host`                                             |
| **Volumes**   | `open-webui-data → /app/backend/data`              |
| **Env**       | `OAI_API_BASE`, `WEBSEARCH_ENGINE`, `SEARXNG_QUERY_URL`, `TERMINAL_SERVER_CONNECTIONS` |

Interface web para interagir com os LLMs via navegador. Configurada para conectar ao proxy llama-swap automaticamente.

| Variável                  | Valor                                        | Descrição                                  |
|---------------------------|----------------------------------------------|--------------------------------------------|
| `OAI_API_BASE`            | `http://localhost:8081/v1`                   | API do proxy llama-swap                    |
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

Gateway WhatsApp com MCP Streamable HTTP em `http://localhost:2785/mcp`. Autenticação via `X-API-Key`/`Bearer` — key gerada na primeira inicialização, salva em `openwa-data/.api-key`. O proxy é o único container do compose com acesso ao Docker socket.

> O openwa também está conectado ao Open WebUI como **tool server MCP** (persistido em `tool_server.connections` no `webui.db`).

---

## manage.sh

Script de gerenciamento via CLI — **reescrito** para o llama-swap (substitui
o antigo ciclo `docker compose` do serviço `llama-cpp`).

### Uso

```bash
./manage.sh start               # Inicia o llama-swap em background (porta 8081)
./manage.sh stop                # Encerra o llama-swap via pidfile
./manage.sh restart             # Para e inicia novamente
./manage.sh status              # Mostra se está rodando
```

### Comportamento interno

| Comando     | Ação                                                                       |
|-------------|-----------------------------------------------------------------------------|
| `start`     | Idempotente (avisa se já rodando); `nohup bin/llama-swap -listen 127.0.0.1:8081 -config llama-swap/config.yaml`, pidfile em `logs/llama-swap.pid`, log em `logs/llama-swap.log`; aguarda a porta responder antes de reportar sucesso |
| `stop`      | SIGTERM no PID do pidfile, fallback SIGKILL após 10 s; limpa o pidfile; sem processo → não falha |
| `restart`   | `stop` + `start`                                                            |
| `status`    | Reporta PID/porta (exit 1 se parado)                                        |

---

## Modelos (llama-swap/config.yaml)

**Fonte da verdade**: [`llama-swap/config.yaml`](llama-swap/config.yaml) —
17 entries (15 stock + 2 Bonsai) com os parâmetros de cada modelo comentados
no próprio YAML. `/v1/models` lista as 17; **2/17 são não-carregáveis**
(`PE_T2I_Heretic`/`PE_I2I_Heretic` — GGUFs ausentes em disco).

| Entry                                   | Engine  | Contexto | Notas                                          |
|-----------------------------------------|---------|----------|------------------------------------------------|
| `Gemma4_12B`                           | stock   | 49152    | Gemma 4 12B IT (Q4_K_XL); multimodal (texto)   |
| `Gemma4_12B_MTP`                       | stock   | 64000    | + drafter MTP; cache split q8_0 (target) + f16 (draft); máx. validado 196608 |
| `Gemma4_12B_Hauhau`                    | stock   | 49152    | Gemma 4 12B Uncensored Balanced (HauhauCS); multimodal (texto, imagem, áudio) |
| `Qwen3.6_28B_A3B`                      | stock   | 49152    | Qwen 3.6 28B-A3B MoE (Q4_K_M); 28 experts CPU  |
| `Qwen3.6_35B_General`                  | stock   | 98304    | Thinking General (Q4_K_M); 32 experts CPU / temp=1.0 / penalidades |
| `Qwen3.6_35B_General_VL`               | stock   | 49152    | Thinking General VL; 28 experts CPU / mmproj pendente |
| `Qwen3.6_35B_Code`                     | stock   | 49152    | Thinking Code; 28 experts CPU / temp=0.6 / sem penalty |
| `Qwen3.6_35B_It_General`               | stock   | 98304    | Instruct General; 32 experts CPU / temp=0.7 / top-p=0.8 |
| `Qwen3.6_35B_It_Reasoning`             | stock   | 98304    | Instruct Reasoning; 32 experts CPU / temp=1.0  |
| `Ornith1.5_9B_MTP`                      | stock   | 65536    | Ornith 1.5 9B MTP (Q4_K_M, protoLabsAI) / acceptance ~0.40 |
| `Ornith1.5_9B_DFlash`                   | stock   | 65536    | Ornith 1.5 9B + DFlash draft (audreyt) / acceptance ~0.42 |
| `Ornith1.5_35B_MTP`                     | stock   | 49152    | Ornith 1.5 35B-A3B MTP (APEX Compact, mudler) / 28 experts CPU / acceptance ~0.80 |
| `Qwen3.6_35B_A3B_Hauhau_Aggressive`    | stock   | 98304    | Qwen 3.6 35B Uncensored Aggressive (HauhauCS) / 32 experts CPU / multimodal |
| `PE_T2I_Heretic`                       | stock   | 16384    | PE Heretic t2i / alias `pe-t2i` — **GGUF ausente em disco** (entry lista mas não carrega) |
| `PE_I2I_Heretic`                       | stock   | 16384    | PE Heretic i2i + mmproj / alias `pe-i2i` — **GGUF/mmproj ausentes em disco** |
| `bonsai-27b`                            | PrismML | 65536    | **Primária** — Bonsai 2 27B PTQ1_0 (5,6 GB) + mmproj Q8_0 (visão validada); ver medições abaixo |
| `bonsai-27b-pq2_0`                      | PrismML | 65536    | **Secundária** — PQ2_0 (6,8 GB, default mais rápido em Ampere); ctx 65536 sem OOM, VRAM total 10250 MiB |
| `Strata` (comentada)                    | Strata  | 65536    | Qwen3.8-Flash-Next (Coder IQ1_M) — modelo ~58 GB **não baixado**; ativar via `strata/README.md` |

### Bonsai 2 27B — medições validadas (task 007, RTX 3060 12 GB)

Entry primária `bonsai-27b` (PTQ1_0 + mmproj Q8_0) com **ctx efetivo 65536**:

| Métrica | Valor medido |
|---------|--------------|
| Prefill | ≈ **540 tok/s** (539,66 em 3410 tokens de prompt) |
| Decode  | ≈ **24,5 tok/s** (128 tokens em 5230,88 ms ⇒ 40,87 ms/token) |
| VRAM    | **9146 MiB** no processo Bonsai; **10657/12288 MiB** total na GPU — sem OOM |

(Nota do config.yaml registrou 9967 MiB totais em execução anterior; a
variação é do display Hyprland/Wayland. Fallback de ctx para 49152 nunca foi
necessário — nota mantida no comentário da entry.) Sampling sem flags
explícitas: os defaults de thinking (temp 1.0, top_p 0.95, top_k 20) vivem
nos metadados do GGUF. **MTP do Bonsai não foi baixado** (fora de escopo).

### Presets Ornith 1.5

Os modelos GGUF oficiais do Ornith 1.5 foram baixados em quantização Q4_K_M: 9B (5.78 GB) e 35B-A3B (21.71 GB). O preset 9B mantém contexto de 65.536 tokens; o 35B-A3B usa contexto de 49.152 tokens e configuração MoE com `-ncmoe 28`. O `mmproj` não foi instalado.

### Preset `Gemma4_12B_MTP` — MTP Speculative decoding

Configura o **Gemma 4 12B IT** com um **drafter MTP** (`mtp-gemma-4-12B-it.gguf`) para speculative decoding por multi-token prediction. Em RTX 3060 12GB alcança **contexto de 196.608 tokens (192K)** a ~**100 tok/s** (~72-85% de aceitação de draft), com 100% na GPU (zero CPU offload). A entry atual usa `-c 64000`; os parâmetros completos vivem comentados na entry do `llama-swap/config.yaml`.

> ⚠️ **Sobre o contexto de 262.144 (256K)**: a config original do post X (ctx=262144) **falha OOM nesta máquina** porque Hyprland/Wayland ocupa ~880 MiB de VRAM da GPU (compartilhada com o display). O máximo validado nesta GPU+sw é **196.608** (192K), que deixa ~100 MiB de folga. Para atingir 256K seria preciso liberar a VRAM do display (GPU dedicada só para display, ou console/tty) ou usar uma GPU com mais VRAM.

**Truque de VRAM — split do KV cache:**

| Cache          | Tipo   | Motivo                                                           |
|----------------|--------|------------------------------------------------------------------|
| Target (K/V)   | `q8_0` | Herdado do macro (`-ctk/-ctv`); economiza VRAM no contexto longo (192K) |
| Draft  (K/V)   | `f16`  | Quantizar o cache do draft derruba a taxa de aceitação; f16 (`-ctkd/-ctvd`) mantém ~70-85% de aceitação |

---

## models.ini — HISTÓRICO (desativado)

> ⚠️ **Desativado** com a migração para o llama-swap (plano
> llama-swap-multi-engine; tasks 002/006). O arquivo
> [`models/models.ini`](models/models.ini) **permanece no repo como
> referência** de config do antigo serviço `llama-cpp` (container fixo com
> `--models-preset`), mas **não é lido por nada**: o serviço saiu do compose
> e o mount `./models.ini → /app/models.ini` foi removido. Os parâmetros de
> cada modelo agora vivem **comentados no `llama-swap/config.yaml`**.

Convenções da tradução INI → flags do llama-server (do cabeçalho do
config.yaml), para leitura do histórico:

| models.ini                    | llama-swap / llama-server                        |
|-------------------------------|--------------------------------------------------|
| `ngl = all`                   | `-ngl 99`                                        |
| `sleep-idle-seconds = 300`    | campo YAML `ttl: 300`                            |
| `alias = <nome>`              | campo YAML `aliases:`                            |
| `cache-type-k/v = q8_0`       | `-ctk q8_0 -ctv q8_0` (macro)                    |
| `cache-reuse = 256`           | `--cache-reuse 256` (macro)                      |
| `parallel = 1`                | `-np 1` (macro)                                  |
| `flash-attn = on` / `jinja = 1` | `-fa on` / `--jinja` (macro)                  |
| `threads = 5`                 | `-t 5` (macro)                                   |
| `cache-ram = 2048`            | `--cache-ram 2048` (macro; override `0` na entry MTP) |
| `n-cpu-moe = N`               | `-ncmoe N`                                       |
| `ctx-size`, `temp`, `top-p`, `top-k`, `min-p`, `presence-penalty`, `repeat-penalty`, `batch-size`, `ubatch-size`, `model-draft`, `spec-type`, `spec-draft-n-max`, `mmproj` | flags homônimas `-c`, `--temp`, `--top-p`, `--top-k`, `--min-p`, `--presence-penalty`, `--repeat-penalty`, `-b`, `-ub`, `--model-draft`, `--spec-type`, `--spec-draft-n-max`, `--mmproj` |

---

## API OpenAI-Compatible

Exposta pelo proxy llama-swap em `127.0.0.1:8081`; o roteamento/swap para o
container do modelo é transparente para o cliente.

### Endpoints

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| `/v1/models` | GET | Lista as entries do `llama-swap/config.yaml` |
| `/v1/chat/completions` | POST | Geração de texto / chat (gatilho do swap) |
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
# Verificar status dos serviços auxiliares
docker compose ps

# Iniciar/parar o serving (llama-swap, processo de host)
./manage.sh start
./manage.sh stop

# Status do llama-swap
./manage.sh status

# Ver logs do serving
tail -f logs/llama-swap.log        # proxy (swap, health checks)
docker logs ls-<Modelo>            # container do modelo carregado

# Testar API
curl http://localhost:8081/v1/models
```

---

## Trocar Modelo Ativo

O llama-swap mantém **1 modelo carregado por vez** (equivale ao antigo
`--models-max 1`) e o swap é **automático por request**: apontar o request
para outro `model` descarrega o container anterior (`docker rm -f
ls-<Anterior>`) e sobe o novo. Não existem mais os endpoints
`load_model`/`unload_model` do serviço antigo, nem edição de `models.ini` —
parâmetros vivem em `llama-swap/config.yaml` (após editar: `./manage.sh
restart`).

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

Flake **recorrente entre sessões e modelos**, documentado na validação e2e
(task 007): após `./manage.sh start`, a primeira carga de um modelo falha
às vezes com `upstream command exited prematurely` no log do llama-swap (o
`docker run` sai com `code=125`). Assinatura recorrente em
`logs/llama-swap.log` (linhas 15, 17, 23, 25, 36/37, 49/50, 105, 121,
140-143) atingindo `Ornith1.5_9B_MTP` (≥2 sessões; chegou a falhar em 4
sessões consecutivas), `bonsai-27b` e `Gemma4_12B`; tipicamente na primeira
carga da sessão (exceção verificada: a linha 121 foi a segunda carga da
sessão). A recuperação pelo retry/health-check seguinte está confirmada
**apenas em parte das ocorrências** (121→122, 140-143→144); nas demais o log
mostra shutdown da sessão sem recuperação, com sucesso só em sessão
posterior. **Causa indeterminada**: a hipótese de transiente do daemon
docker nunca foi provada; a de conflito de nome com container órfão está
**enfraquecida** pela assepsia prévia registrada no log (`logs/llama-swap.log:35`:
`docker rm -f ls-<Modelo>` antes do `docker run`, e ainda assim `exit 125`
na linha 36). Workaround: repetir o request ou `./manage.sh restart`.
Follow-up: na próxima ocorrência, capturar stderr do `docker run` /
`docker events`.

### Entries PE sem GGUF em disco

`PE_T2I_Heretic` e `PE_I2I_Heretic` aparecem no `/v1/models` mas os
diretórios `models/pe_t2i_heretic-Q4_K_M/` e `models/pe_i2i_heretic-Q4_K_M/`
estão vazios — as entries **não carregam** (2/17 não-funcionais) até os
GGUFs serem baixados; nota também nos comentários das entries do config.yaml.

### Storage cheio

```bash
# Verificar uso
du -sh models/*/

# Limpar modelos não usados
rm -rf models/NOME_DO_MODELO/
```
