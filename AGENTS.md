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
./manage.sh start|stop|restart|status   # TUDO: llama-swap (HOST) + compose (webui, terminal, searxng, comfyui, mcps, openwa)
./manage.sh swap|services start|stop    # controle fino: só o proxy, ou só o compose
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
  modelo (18 entries: 16 stock + 1 Bonsai + 1 Xing).
  `models/models.ini` é HISTÓRICO desativado — nada o lê.
  **Convenção de contexto** (VRAM validada por carga real, display idle):
  entry SEM sufixo = **64k** (floor); `_XXk` = contexto maior validado;
  `_32k` = não alcança o floor. Com jogos no desktop (1,8+ GB VRAM) as
  variantes longas de MoE híbrido podem OOM.
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
   embutidos — Qwen3.6-MTP, Saluki, Ornith-MTP): usar `--spec-type draft-mtp`
   **sem** `--model-draft`; nesse modo `-ctkd/-ctvd` NÃO afetam a aceitação
   (medido: idêntico com q8_0 vs f16) — o draft consome o estado residual do
   target, não cache próprio. Para drafts separados (Gemma MTP, DFlash) usar
   `--model-draft` + `-ctkd f16 -ctvd f16` (quantizar KV do draft derruba a
   aceitação). Medições (Gemma4_12B, 2 prompts): **temperatura NÃO afeta a
   aceitação do draft** (0,46-0,48 em temp 0.0/0.6/1.0 — hipótese refutada);
   o que afeta é `--spec-draft-n-max`: sweet spot 3-4, acima de 6 a
   aceitação por draft colapsa e o tok/s cai (~60% do pico em n=8).
 6. Open WebUI: `WEBSEARCH_ENGINE`, `SEARXNG_QUERY_URL`,
    `TERMINAL_SERVER_CONNECTIONS` e `TOOL_SERVER_CONNECTIONS` são persistidos
    no `webui.db` na primeira inicialização — **o banco tem precedência sobre
    o env** depois disso (registrar MCP = escrever na chave
    `tool_server.connections` do banco, não no compose). SearXNG precisa de
    `formats: [html, json]` no `data/searxng/settings.yml`.
 7. **Prefill de MoE com experts na CPU é dominado por streaming de pesos —
    `-ub 2048` dobra o prefill.** Medido 2026-10-11 (Qwen3.6_35B_Code, prompt
    5,6k tok, display idle): ub512→400 tok/s; ub1024→594; ub2048→865-909
    (VRAM +~650 MiB → 11,4-11,5 GB); ub4096 NÃO cabe (compute buffer estoura;
    `common_fit_params ... abort` com `-ngl 99`). Decode inalterado (~26-28
    tok/s, aceitação MTP idêntica). `-b 8192` não ajuda (820 < 908). Aplicado:
    `-ub 2048` nas entries Qwen3.6 64k + Ornith1.5_35B; `-ub 1024`
    nas `_96k`, Xing e Saluki (folga de VRAM). Motivo: com `-ncmoe`, cada
    ubatch relê os pesos dos experts na RAM; ubatch maior amortiza o custo.
    Nota: KV do Qwen3.6 é pequeno (só 10/41 camadas têm KV; 2 heads × 256 →
    ~10,6 KiB/tok em q8_0) — o gargalo é FFN de experts, não attention.
 8. **Geração de imagem (ComfyUI) e inferência de LLM dividem a mesma VRAM —
    liberação bidirecional automática.** O ComfyUI
    (yanwk/comfyui-boot, porta 8188 via gpu-shim; núcleo em 127.0.0.1:8189)
    roda com `--disable-smart-memory`: ao fim de cada geração os pesos
    voltam para RAM e a VRAM cai para ~190 MiB. No sentido inverso, o
    gpu-shim (`comfyui/user-scripts/gpu-shim.py`) avalia a VRAM livre no
    caminho de geração (Open WebUI/API; polling da UI nativa nunca
    descarrega) e, se < 8 GiB, chama `GET :8081/unload` do llama-swap
    (síncrono) antes de repassar o request. `./manage.sh unload` usa o
    mesmo endpoint. Sem isso a carga do LLM ou do DiT dá OOM de compute
    buffer (`VRAM grow failed` no log do ComfyUI = DiT carregou com LLM
    residente).
 9. **KV cache NÃO sobrevive ao unload/swap — e `--slot-save-path` NÃO
    resolve (ainda).** O KV cache vive no processo do `llama-server`: quando
    o llama-swap remove o container `ls-*` (unload do gpu-shim, swap ou
    `ttl: 300`), a conversa é re-prefil inteira no retorno. O
    `--slot-save-path` + `/slots/0?action=save|restore` **parece** funcionar
    (save/restore respondem 200 com `n_restored == n_saved`) mas em modelos
    **híbridos/recorrentes e SWA** o reuso é ZERO — o formato não serializa
    os context checkpoints e o servidor cai em `forcing full prompt
    re-processing` (bug ggml-org/llama.cpp#28194; medido aqui no LFM2.5:
    `cache_n: 0` com LCP similarity 1.000). Quase todo o nosso zoológico é
    híbrido/SWA (Qwen3.6/3.8 GDN, LFM2.5, Saluki, Gemma4 SWA). Decisão
    (2026-10-12): **aguardar fix no upstream**; se um dia for urgente, os
    caminhos mapeados são o patch `--slot-save-checkpoints` do ky095n
    (comentário do issue) ou o fork prompt-disk-cache do qqkzlm (snapshot
    automático, medido no Qwen3.6-35B: prefill 40k tokens 151 s → 1,35 s).
    O custo hoje: re-prefill ~870-900 tok/s (Qwen3.6, ub2048) + recarga fria
    de pesos (10-30 s) — só na primeira mensagem após imagem/swap.

---

## Modelos (RTX 3060 12 GB — medições e2e)

| Entry | Engine | Ctx | Notas / tok/s medido |
|-------|--------|-----|----------------------|
| `Gemma4_12B` | stock | 65536 | Gemma 4 12B IT QAT; multimodal (texto) |
| `LFM2.5_24B_A2B` | stock | 65536 | LiquidAI raciocínio puro agêntico, MoE 24B/2,45B (64 experts top-4); ncmoe 20 + `--load-mode none` + ub2048; **~45 tok/s, prefill ~1900 tok/s**; VRAM 9809 MiB; sampling temp 0.1 / top-k 50 / rep 1.05; sem MTP (draft DSpark não publicado) |
| `Qwen3.8_35B_Distill` | stock | 65536 | Qwen3.8-35B-A3B-Distill Q4_K_M (empero-ai; GGUF no repo `-GGUF`, o sem sufixo só tem safetensors); arch qwen35moe idêntica ao Qwen3.6, MTP embutido (nextn=1); ncmoe 28 + `--load-mode none` + ub2048; **~35 tok/s, prefill ~900 tok/s, aceitação ~0,62**; VRAM 10839 MiB |
| `MiniCPM-V_4.7_35B` | stock | 65536 | MiniCPM-V 4.7 35B-A3B multimodal Q4_K_M + mmproj f16 (openbmb `-gguf`); backbone Qwen3.6 (arch qwen35moe, 256 experts/8 ativos, GDN); **SEM MTP** (header declara nextn=1 mas sem tensors; draft DSpark testado e descartado: aceitação ~10%, decode 9,5 tok/s, buffer ~3,9 GB não cabe — GGUF do draft guardado em `models/MiniCPM-V-4.7-35B-A3B-DSpark/`); ncmoe 32 + `--load-mode none` + ub2048; requer llama.cpp ≥ PR #29416 (imagem stock atualizada p/ build 11561, fingerprint `b11561-e937b17a2`); **~32-35 tok/s, prefill ~1040 tok/s**; VRAM 8991 MiB; visão validada |
| `Qwen3.6_35B_General` | stock | 65536 | thinking + head MTP; ncmoe 32; ub2048; aceitação ~82-93% |
| `Qwen3.6_35B_Code` | stock | 65536 | thinking + head MTP; ncmoe 28; **~27 tok/s, aceitação 93%** — MoE híbrido padrão; **ub2048: prefill ~890 tok/s (era ~400), VRAM ~11,5 GB** |
| `Qwen3.6_35B_It_General` / `_It_Reasoning` | stock | 65536 | Instruct (sem/temp thinking); ncmoe 32; ub2048 |
| `Qwen3.6_35B_A3B_Hauhau_Aggressive` | stock | 65536 | Uncensored Aggressive, multimodal; ncmoe 28 (otimizado 2026-10-14 p/ teto 10 GB); ub2048 + `--load-mode none`; **prefill ~1150 tok/s, decode ~39 tok/s, VRAM processo ~9,6 GB**; SEM MTP (GGUF sem tensors nextn — spec inaplicável; `--moe-cache-mib` testado e rejeitado: decode -21%) |
| `Ornith1.5_35B_MTP` | stock | 65536 | agêntico (APEX Compact), ncmoe 28 + `--load-mode none` (faltava — regra 2); ub2048: prefill ~990 tok/s, VRAM 9849 MiB, aceitação ~0,80 |
| `bonsai-27b` | PrismML | 65536 | PTQ1_0 + mmproj (visão validada); 24,5 tok/s, VRAM 10657/12288 total (PQ2_0 removida 2026-10-13) |
| `Xing4.0_29B_A4B` | Xing | 65536 | MoE 29B/4B + MLA + mHC; `--load-mode none` + ncmoe 24; ub1024: prefill ~543 tok/s, VRAM 11177 MiB; ~12,5 tok/s |
| **Variantes _XXk** | | | |
| `Gemma4_12B_128k` | stock | 131072 | Gemma 4 12B @ 128K validada: 9487 MiB c/ mmproj |
| `Qwen3.6_35B_General_96k` / `_Code_96k` / `_It_General_96k` / `_It_Reasoning_96k` / `_A3B_Hauhau_Aggressive_96k` | stock | 98304 | ub1024 (ub2048 não cabe c/ 96k); Code c/ ncmoe 28: 11577 MiB validado (apertado); General/It_* ncmoe 32 — só com display idle; `_Hauhau_96k` ncmoe 28 (2026-10-14, teto 10 GB): **prefill ~750 tok/s (+5-8%), decode 33-40 (banda de contenção do desktop), VRAM ~10000-10044 MiB (margem ~200 MB — pode falhar a carga com pico no desktop; fallback: voltar a 32)** |

> **Removidos em 2026-10-13** (liberação de disco, GGUFs apagados + entries
> retiradas do config): LFM2.5-8B-A1B-Hermes (`LFM2.5_8B_A1B_Hermes`/`_128k`),
> Gemma4-12B-agentic-fable5 (`Gemma4_12B_Agentic`/`_128k`), Underdog-Saluki-27B
> (`Saluki27B_Qwen3.8_32k`), Qwen3.8-27B-GSQ-RCO-IQ2_XS
> (`Qwen3.8_27B_GSQ_IQ2_XS_32k`), Bonsai PQ2_0 (`bonsai-27b-pq2_0`; mantido
> só o PTQ1_0, o menor) e Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced
> (`Gemma4_12B_Hauhau`/`_Hauhau_128k` + drafter MTP: `Gemma4_12B_MTP`/`_MTP_128k`
> — o draft morava no mesmo dir) e Mellum2.1-12B-A2.5B-Thinking
> (`Mellum2.1_12B_A2.5B`). ~49,5 GB liberados no total. **Strata**
> (`Strata`, Qwen3.8-Flash-Next Coder IQ1_M) removida em 2026-10-14: pesos
> 86G apagados do disco (worst prefill do zoológico, ~8 tok/s); imagem da
> engine e infra de build preservadas — reativável via
> `engines/strata/README.md`.

Relevância para servir (uso agêntico/opencode): **alta** = Qwen3.6_35B_Code/General,
Qwen3.8_35B_Distill, bonsai-27b,
MiniCPM-V_4.7_35B, Gemma4_12B, LFM2.5_24B_A2B; **média** =
Xing, Ornith 35B, It_*.

---

## docker-compose (serviços auxiliares — sem o serving)

`open-webui` (host `:8080`, conecta ao proxy via `OAI_API_BASE`,
`WEBUI_SECRET_KEY` obrigatório p/ persistir tokens OAuth/MCP) ·
`open-terminal` (execução agêntica `:8000`, requer modelo com Function
Calling = Native) · `searxng` (`:8888`, JSON habilitado) · `openwa` +
`openwa-docker-proxy` (WhatsApp/MCP `:2785/mcp`, key em
`data/openwa/.api-key`; o proxy é o único container com acesso ao Docker
socket) · `mcp-playwright` (`:8931/mcp`, `mcr.microsoft.com/playwright/mcp`
pinado, headless) · `mcp-memory` (`:8932/mcp`, supergateway faz a ponte
stdio→Streamable HTTP do `@modelcontextprotocol/server-memory`; grafo em
`mcp-data/memory.json`, **compartilhado com o memory do opencode** —
`MEMORY_FILE_PATH` aponta para esse caminho) · `comfyui` (`:8188`,
yanwk/comfyui-boot pinado; Qwen-Image 2.1 Turbo int8, geração + edição,
integrado ao Open WebUI). Detalhes: `DOCKER.md`.

> **Estado no repo (2026-10-14)**: os serviços do compose não usam mais
> volumes nomeados do Docker — tudo em binds `./data/<serviço>/`
> (gitignored): `data/open-webui/` (webui.db, uploads, RAG),
> `data/open-terminal/`, `data/openwa/` (+ `.api-key` e sessions),
> `data/9router/`, `data/comfyui/` (caches hf/torch), `data/searxng/`
> (`settings.yml` com secret). O `webui.db` fica assim visível/backupável;
> lembrar que o banco tem precedência sobre o env (regra 6).

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
- **Swap "lento" entre modelos**: o container NÃO é o gargalo — medido
  2026-10-11 (GPU idle): Docker kill→create→start ~0,7 s; `docker run` →
  health com GGUF na page cache 2,4 s; swap Gemma↔LFM com cache quente 3,7 s;
  com GGUF frio 10–30 s. O custo real é recarregar pesos com a page cache
  fria: 31 GiB de RAM não seguram o cache quando Qwen3.6 (22 GB,
  `--load-mode none`) e Strata (~30 GB travados) rodam — depois deles todo
  swap vira leitura fria do NVMe. O llama-swap v263 NÃO reusa container
  entre entries (o multi-model nativo do llama-server `/models/load` foi
  removido do binário; `groups`/`matrix` só orquestram processos
  concorrentes). Alavanca disponível se um dia valer a pena:
  `filters.setParamsByID` funde variants que diferem só em sampling num
  único entry (mesmo processo, zero swap) — não aplicada.
- **YAML inválido**: `./manage.sh restart` morre na inicialização — o erro
  aparece no fim de `logs/llama-swap.log` (ex.: chave duplicada no entry).
- **Storage**: `du -sh models/*/` — repo agora no **NVMe** (`/home/jocic/oraculo`,
  migrado do SATA 220 GB em 2026-10-14); GGUFs órfãos (sem entry no
  config) são candidatos a remoção.
