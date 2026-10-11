# oraculo — instruções para agentes

Servidor local de LLMs: **llama-swap** (proxy multi-engine em `127.0.0.1:8081`,
sobe um container Docker efêmero de llama.cpp por modelo sob demanda) +
**Open WebUI** (`:8080`) + Open Terminal (`:8000`), SearXNG (`:8888`), OpenWa
(`:2785`). Hardware alvo: **RTX 3060 12 GB** (GPU **compartilhada** com o
desktop pessoal) + 32 GB RAM + NVMe.

**Regra do repo**: toda mudança deve ser refletida na documentação —
`docker-compose.yml` → `DOCKER.md`; `llama-swap/config.yaml` ou modelos →
`AGENTS.md`; `manage.sh`/fluxo de uso → `README.md`; requisitos → `README.md`.

---

## Comandos essenciais

```bash
./manage.sh start|stop|restart|status   # llama-swap (processo de HOST, fora do compose)
docker compose ps                       # serviços auxiliares (webui, terminal, searxng, openwa)
tail -f logs/llama-swap.log             # log do proxy (swap, health checks)
docker logs ls-<Modelo>                 # log do container do modelo carregado

# Testar modelo (o primeiro request dispara a carga; swap automático entre modelos)
curl -s http://localhost:8081/v1/models
curl -s http://localhost:8081/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"<Entry>","messages":[{"role":"user","content":"oi"}],"max_tokens":50}'
# timings no response: prompt_per_token_ms, predicted_per_token_ms, draft_n_accepted
```

Após editar `llama-swap/config.yaml`: `./manage.sh restart`. Não há
load/unload manual — apontar o request para outro `model` faz o swap
(`docker rm -f ls-<Anterior>`); descarrega sozinho após 5 min ocioso (`ttl: 300`).

---

## Arquitetura

- **`llama-swap/config.yaml` é a FONTE DA VERDADE** dos parâmetros de cada
  modelo (17 entries: 14 stock + 2 Bonsai + 1 Xing; `/v1/models` lista as 17,
  todas carregáveis). `models/models.ini` é HISTÓRICO desativado — nada o lê.
- Macros no config: `docker-stock` (imagem oficial
  `ghcr.io/ggml-org/llama.cpp:full-cuda`, entrypoint `/app/llama-server`),
  `docker-prismml` e `docker-xing` (imagens locais, entrypoint
  `/usr/local/bin/llama-server`), `docker-stop`.
- **O llama-swap NÃO executa o cmd via shell (shlex)**: nada de `;`, pipes ou
  redirects no `cmd` — um único comando por entry.
- Engines dedicadas vivem em `engines/<fork>/` (Dockerfile + build.sh),
  clonando o fork **pinado em commit** (o build falha se HEAD ≠ pin):
  - `engines/llama.cpp-prismml/` — commit `84445367f` (branch `prism`)
  - `engines/llama.cpp-xing/` — commit `8c379195a` (branch `xing4_0-port`)
  - Verificar engine em runtime: `system_fingerprint` nos responses
    (`b1-8444536` PrismML, `b1-8c37919` Xing).
- Instalar modelo novo: guia em `models/MODELS_INSTALL.md`
  (`hf download ... --local-dir models/<Dir>` + entry no config + restart).

---

## Regras duras (erros que já custaram horas)

1. **NUNCA servir Bonsai 2 nem Xing4.0 com a imagem stock.**
   - Bonsai (ternários PTQ1_0/PQ2_0): kernels só no fork PrismML; stock recusa
     ou carrega como Q2_0 legacy gerando lixo.
   - Xing4.0 (arquitetura `xing4_0`): suporte só no fork shuxiaoqiong (PR
     ggml-org#29012, não mergeado); stock recusa o GGUF.
2. **MoE híbrido exige `--load-mode none`** nas entries com `-ncmoe`. Com
   mmap + overrides de tensor para CPU o decode desaba silenciosamente
   (medido: Xing 1,2→12,5 tok/s; Qwen3.6 MTP 1,3→27-33 tok/s). O loader
   avisa: `tensor overrides to CPU are used with mmap enabled`.
3. **A GPU é compartilhada com o desktop/jogos.** Antes de diagnosticar
   `exit 125`/falha de carga, rode `nvidia-smi`: um jogo pode estar ocupando
   1-2 GB (causa real já observada: OOM de compute buffer, não flake do
   daemon). Display Hyprland/Wayland ocupa ~880 MiB em idle.
4. **Flake real `exit 125`** também existe (transiente na primeira carga após
   restart, múltiplos modelos/sessões): retry do request ou `./manage.sh
   restart` resolve. Capturar stderr de `docker run`/`docker events` na
   próxima ocorrência para provar a causa.
5. **Speculative decoding MTP self-draft** (GGUFs com tensors `nextn`
   embutidos — Qwen3.6-MTP, Ornith-MTP): usar `--spec-type draft-mtp`
   **sem** `--model-draft`. Para drafts separados (Gemma MTP, DFlash) usar
   `--model-draft` + `-ctkd f16 -ctvd f16` (quantizar KV do draft derruba a
   aceitação).
6. Open WebUI: `WEBSEARCH_ENGINE`, `SEARXNG_QUERY_URL` e
   `TERMINAL_SERVER_CONNECTIONS` são persistidos no `webui.db` na primeira
   inicialização — **o banco tem precedência sobre o env** depois disso.
   SearXNG precisa de `formats: [html, json]` no `searxng/settings.yml`.

---

## Modelos (RTX 3060 12 GB — medições e2e)

| Entry | Engine | Ctx | Notas / tok/s medido |
|-------|--------|-----|----------------------|
| `Gemma4_12B` | stock | 49152 | Gemma 4 12B IT QAT; multimodal (texto) |
| `Gemma4_12B_MTP` | stock | 64000 | drafter MTP separado; ~100 tok/s, aceitação ~72-85%; máx validado 196608 (256K falha OOM pelo display) |
| `Gemma4_12B_Hauhau` | stock | 49152 | Uncensored Balanced; multimodal (texto, imagem, áudio) |
| `Gemma4_12B_Agentic` | stock | 49152 | agentic fable5/tau2, denso 100% VRAM (7,4 GB); **~24 tok/s, prefill 8 ms/tok** — worker de workflows |
| `Mellum2.1_12B_A2.5B` | stock | 49152 | JetBrains código thinking, MoE cabe inteiro (8,1 GB); **~90 tok/s** |
| `LFM2.5_8B_A1B_Hermes` | stock | 49152 | Hermes agentic, MoE cabe inteiro (5,2 GB); **~129 tok/s** — smoke tests |
| `Qwen3.6_35B_General` | stock | 98304 | thinking + head MTP; ncmoe 32; aceitação ~82-93% |
| `Qwen3.6_35B_Code` | stock | 49152 | thinking + head MTP; ncmoe 28; **~27 tok/s, aceitação 93%** — MoE híbrido padrão |
| `Qwen3.6_35B_It_General` / `_It_Reasoning` | stock | 98304 | Instruct (sem/temp thinking); ncmoe 32 |
| `Qwen3.6_35B_A3B_Hauhau_Aggressive` | stock | 98304 | Uncensored Aggressive, multimodal; ncmoe 32 |
| `Ornith1.5_9B_MTP` / `_9B_DFlash` | stock | 65536 | aceitação baixa (~0,40-0,42) — candidatos a remoção |
| `Ornith1.5_35B_MTP` | stock | 49152 | agêntico (APEX Compact), ncmoe 28, aceitação ~0,80 |
| `bonsai-27b` | PrismML | 65536 | PTQ1_0 + mmproj (visão validada); 24,5 tok/s, VRAM 10657/12288 total |
| `bonsai-27b-pq2_0` | PrismML | 65536 | PQ2_0, mais rápido em Ampere, sem visão |
| `Xing4.0_29B_A4B` | Xing | 49152 | MoE 29B/4B + MLA + mHC; `--load-mode none` + ncmoe 24; ~12,5 tok/s |
| `Strata` (comentada) | strata | 65536 | modelo ~58 GB não baixado; ativar via `strata/README.md` |

Relevância para servir (uso agêntico/opencode): **alta** = Gemma4_12B_Agentic,
Qwen3.6_35B_Code/General, bonsai-27b, Gemma4_12B; **média** = LFM/Mellum,
Xing, Ornith 35B, Hauhau, bonsai-pq2_0, It_*; **baixa** = Ornith 9B (×2).

---

## docker-compose (serviços auxiliares — sem o serving)

`open-webui` (host `:8080`, conecta ao proxy via `OAI_API_BASE`,
`WEBUI_SECRET_KEY` obrigatório p/ persistir tokens OAuth/MCP) ·
`open-terminal` (execução agêntica `:8000`, requer modelo com Function
Calling = Native) · `searxng` (`:8888`, JSON habilitado) · `openwa` +
`openwa-docker-proxy` (WhatsApp/MCP `:2785/mcp`, key em
`openwa-data/.api-key`; o proxy é o único container com acesso ao Docker
socket). Detalhes: `DOCKER.md`.

> Design: stack request-driven e **deliberadamente não-autônomo** — sem
> agentes/workflows em background que possam requerer VRAM sem supervisão
> (GPU compartilhada). `-np 1` em todas as entries (single-user).

---

## Troubleshooting rápido

- **Modelo não carrega**: GGUF existe em `models/<dir>/`? →
  `tail -n 50 logs/llama-swap.log` → `docker logs ls-<Modelo>` (enquanto Up).
- **Falha de carga / `exit 125`**: primeiro `nvidia-smi` (jogo/desktop
  ocupando VRAM → OOM de compute buffer); senão, retry ou restart (flake
  conhecido).
- **Decode absurdamente lento em MoE**: falta `--load-mode none` (regra 2).
- **YAML inválido**: `./manage.sh restart` morre na inicialização — o erro
  aparece no fim de `logs/llama-swap.log` (ex.: chave duplicada no entry).
- **Storage**: `du -sh models/*/` — SSD 220 GB; GGUFs órfãos (sem entry no
  config) são candidatos a remoção.
