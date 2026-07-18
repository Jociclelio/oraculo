# Instalação de Modelos LLM

Este guia explica como instalar e configurar modelos GGUF no servidor oráculo.

---

## Estrutura

```
models/
├── models.ini                # Configuração do servidor llama.cpp
├── MODELS_INSTALL.md         # Este arquivo
├── Bonsai-27B-Q1_0/
│   └── modelo.gguf
├── Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced/
│   └── modelo.gguf
└── ...
```

Cada modelo tem sua própria subpasta contendo o arquivo `.gguf` e arquivos auxiliares (mmproj, mtp, etc.).

---

## Pré-requisitos

- **10-100 GB** de disco livre por modelo (dependendo do tamanho e quantização)
- Acesso à internet para download dos modelos

---

## Passo a Passo

### 1. Escolher o Modelo

Consulte a lista de modelos disponíveis em [`AGENTS.md`](../AGENTS.md#modelos-disponíveis).

### 2. Criar a Pasta do Modelo

```bash
mkdir -p models/NOME_DO_MODELO/
```

### 3. Baixar o Modelo GGUF

Use `wget` ou `curl` para baixar o arquivo do repositório Hugging Face:

```bash
cd models/NOME_DO_MODELO/
wget https://huggingface.co/usuario/modelo/resolve/main/modelo.gguf
```

> **Dica:** Modelos quantizados (Q4_K_M, Q5_K_M) oferecem bom equilíbrio entre qualidade e tamanho.

### 4. Configurar no models.ini

Adicione uma seção no arquivo [`models.ini`](models.ini) com as configurações do modelo:

```ini
[NOME_DO_MODELO]
model = /models/NOME_DO_MODELO/modelo.gguf
ctx-size = 49152
ngl = all
temp = 0.7
top-p = 0.95
top-k = 64
```

### 5. Recarregar o Servidor

```bash
# Recarregar o modelo sem reiniciar o container
curl -X POST http://localhost:8081/v1/load_model \
  -H "Content-Type: application/json" \
  -d '{"model_alias": "NOME_DO_MODELO"}'
```

---

## Parâmetros Comuns

| Parâmetro | Descrição | Valores típicos |
|-----------|-----------|-----------------|
| `model` | Caminho ao `.gguf` | `/models/NOME/modelo.gguf` |
| `ctx-size` | Tamanho do contexto | `49152`, `65536` |
| `ngl` | Camadas na GPU | `all`, `45`, `80` |
| `temp` | Temperatura | `0.6` (código), `1.0` (geral) |
| `top-p` | Amostragem top-p | `0.9`, `0.95` |
| `top-k` | Amostragem top-k | `16`, `32`, `64` |
| `mmproj` | Arquivo multimodal | `/models/NOME/mmproj-model-f16.gguf` |
| `model-draft` | Modelo draft (MTP) | `/models/NOME/modelo-draft.gguf` |

---

## Modelos Multimodais

Modelos com capacidade visual (imagem) requerem um arquivo `mmproj`:

```ini
[NOME_MULTIMODAL]
model = /models/NOME/modelo.gguf
mmproj = /models/NOME/mmproj-model-f16.gguf
```

Baixe o arquivo mmproj do mesmo repositório Hugging Face do modelo.

---

## Modelos MoE (Mixture of Experts)

Modelos MoE (ex: Qwen 35B-A3B) usam `n-cpu-moe` para distribuir experts na CPU:

```ini
[NOME_MOE]
model = /models/NOME/modelo.gguf
n-cpu-moe = 24
```

---

## Modelos com MTP (Multi-Token Prediction)

Para acelerar a geração, use um modelo draft:

```ini
[NOME_MTP]
model = /models/NOME/modelo.gguf
model-draft = /models/NOME/modelo-draft.gguf
```

---

## Verificação

Após instalar, verifique se o modelo está funcionando:

```bash
# Listar modelos
curl http://localhost:8081/v1/models

# Testar inferência
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "NOME_DO_MODELO",
    "messages": [{"role": "user", "content": "Olá!"}],
    "temperature": 0.7
  }'
```

---

## Dicas

- **Quantização**: Q4_K_M é o ponto de equilíbrio entre qualidade e tamanho. Q3 pode perder qualidade, Q5/Q6 é mais pesado sem ganho significativo.
- **Contexto**: `ctx-size` maior consome mais memória. Use 49152 como padrão, 65536 apenas se a GPU permitir.
- **Flash Attention**: Ative com `flash-attn = on` (configuração global no `[*]`) para melhor performance.
- **Monitorar VRAM**: Use `nvidia-smi` para verificar o uso de memória durante a inferência.
