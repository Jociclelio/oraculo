# oraculo

Servidor local de LLMs rodando com `llama.cpp` via Docker, com API OpenAI-compatible na porta 8081.

---

## Estrutura do Repositório

```
oraculo/
├── docker-compose.yml          # Definição do serviço Docker (llama-cpp)
├── manage.sh                   # Script de gerenciamento (start/stop)
├── models.ini                  # Configurações dos modelos para o servidor llama.cpp
├── .env                        # Variáveis de ambiente
│
└── models/                     # Modelos GGUF e arquivos auxiliares (mmproj, mtp, etc.)
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

---

## docker-compose.yml

Define **um serviço** para inferência de LLM com GPU:

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
