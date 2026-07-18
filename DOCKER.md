# Docker — Servidor LLM com llama.cpp

Servidor local de LLM com **llama.cpp** (inferência GPU) via Docker, expondo API OpenAI-compatible na porta 8081 e interface web **Open WebUI** na porta 3000.

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
- **GPU**: 1× NVIDIA GPU
- **Volume**: `./models → /models` (modelos GGUF)
- **Config**: `./models/models.ini → /app/models.ini`

Serve uma **API OpenAI-compatible** para geração de texto, chat e embeddings.

### open-webui — Interface Web

- **Imagem**: `ghcr.io/open-webui/open-webui:main`
- **Container**: `open-webui`
- **Porta**: `3000`
- **Volume**: `open-webui-data → /app/backend/data` (dados persistentes)
- **Dependência**: `llama-cpp`

Interface web para interagir com os modelos via navegador. Configurada automaticamente para conectar ao llama-cpp.

---

## Gerenciamento

### Docker Compose (todos os serviços)

```bash
# Iniciar todos os serviços
docker compose up -d

# Parar todos os serviços
docker compose down

# Ver status
docker compose ps

# Ver logs
docker compose logs -f
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

Acessar a interface web em **http://localhost:3000**.

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
└── .env                      # Variáveis de ambiente
```

---

## Backup

```bash
# Backup da config dos modelos
tar -czf models-config-backup.tar.gz models/models.ini

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

### Open WebUI não conecta ao llama-cpp

```bash
# Verificar se o llama-cpp está rodando
docker ps | grep llama-cpp

# Verificar se a API está respondendo
curl http://localhost:8081/v1/models

# Reiniciar o open-webui
docker restart open-webui
```
