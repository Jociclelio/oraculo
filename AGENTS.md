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
  modelo (32 entries: 29 carregáveis = 25 stock + 2 Bonsai + 1 Xing + 1
  Strata). `models/models.ini` é HISTÓRICO desativado — nada o lê.
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
 6. Open WebUI: `WEBSEARCH_ENGINE`, `SEARXNG_QUERY_URL` e
    `TERMINAL_SERVER_CONNECTIONS` são persistidos no `webui.db` na primeira
    inicialização — **o banco tem precedência sobre o env** depois disso.
    SearXNG precisa de `formats: [html, json]` no `searxng/settings.yml`.
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

---

## Modelos (RTX 3060 12 GB — medições e2e)

| Entry | Engine | Ctx | Notas / tok/s medido |
|-------|--------|-----|----------------------|
| `Gemma4_12B` | stock | 65536 | Gemma 4 12B IT QAT; multimodal (texto) |
| `Gemma4_12B_MTP` | stock | 65536 | drafter MTP separado; ~100 tok/s; máx validado 196608 (256K falha OOM pelo display) |
| `Gemma4_12B_Hauhau` | stock | 65536 | Uncensored Balanced; multimodal (texto, imagem, áudio) |
| `Gemma4_12B_Agentic` | stock | 65536 | agentic fable5/tau2, denso 100% VRAM (7,4 GB); **~24 tok/s, prefill 8 ms/tok** — worker de workflows |
| `Mellum2.1_12B_A2.5B` | stock | 65536 | JetBrains código thinking, MoE cabe inteiro (8,1 GB); **~90 tok/s** |
| `LFM2.5_8B_A1B_Hermes` | stock | 65536 | Hermes agentic, MoE cabe inteiro (5,2 GB); **~129 tok/s** — smoke tests |
| `Saluki27B_Qwen3.8_32k` | stock | 32768 | Qwen3.8-27B build 2-bit (Underdog/Kujira + head MTP), denso 100% VRAM (8,35 GB); best tool-calling (Underdog Bench 88/120, SWE-bench 30/50); **~31 tok/s, aceitação ~76%**; ctx máx 32K (64K estoura 12 GB) — entry abaixo do floor de 64k; ub1024: VRAM 11371 MiB, prefill ~429 tok/s (ub2048 não ajuda, VRAM 11823 apertado) |
| `Qwen3.8_35B_Distill` | stock | 65536 | Qwen3.8-35B-A3B-Distill Q4_K_M (empero-ai; GGUF no repo `-GGUF`, o sem sufixo só tem safetensors); arch qwen35moe idêntica ao Qwen3.6, MTP embutido (nextn=1); ncmoe 28 + `--load-mode none` + ub2048; **~35 tok/s, prefill ~900 tok/s, aceitação ~0,62**; VRAM 10839 MiB |
| `Qwen3.8_27B_GSQ_IQ2_XS_32k` | stock | 32768 | Qwen3.8-27B GSQ-RCO IQ2_XS `-mtp` (ISTA; não-uniforme 2,50 bpw IQ1_M..Q6_K, híbrido qwen35 GDN); ctx máx 32K (KV híbrido ~32 KiB/tok; 64K estoura); **~31 tok/s, aceitação ~0,70**, prefill ~433 tok/s; VRAM 11539 MiB (apertado) |
| `Qwen3.6_35B_General` | stock | 65536 | thinking + head MTP; ncmoe 32; ub2048; aceitação ~82-93% |
| `Qwen3.6_35B_Code` | stock | 65536 | thinking + head MTP; ncmoe 28; **~27 tok/s, aceitação 93%** — MoE híbrido padrão; **ub2048: prefill ~890 tok/s (era ~400), VRAM ~11,5 GB** |
| `Qwen3.6_35B_It_General` / `_It_Reasoning` | stock | 65536 | Instruct (sem/temp thinking); ncmoe 32; ub2048 |
| `Qwen3.6_35B_A3B_Hauhau_Aggressive` | stock | 65536 | Uncensored Aggressive, multimodal; ncmoe 32; ub2048 + `--load-mode none` (faltava — regra 2) |
| `Ornith1.5_9B_MTP` / `_9B_DFlash` | stock | 65536 | aceitação baixa (~0,40-0,42) — candidatos a remoção |
| `Ornith1.5_35B_MTP` | stock | 65536 | agêntico (APEX Compact), ncmoe 28 + `--load-mode none` (faltava — regra 2); ub2048: prefill ~990 tok/s, VRAM 9849 MiB, aceitação ~0,80 |
| `bonsai-27b` | PrismML | 65536 | PTQ1_0 + mmproj (visão validada); 24,5 tok/s, VRAM 10657/12288 total |
| `bonsai-27b-pq2_0` | PrismML | 65536 | PQ2_0, mais rápido em Ampere, sem visão |
| `Xing4.0_29B_A4B` | Xing | 65536 | MoE 29B/4B + MLA + mHC; `--load-mode none` + ncmoe 24; ub1024: prefill ~543 tok/s, VRAM 11177 MiB; ~12,5 tok/s |
| `Strata` | Strata | 65536 | Qwen3.8-Flash-Next Coder IQ1_M (engine Niko1221/Strata); pesos+pack em `/home/jocic/strata-data` (~86 GB NVMe), **~30 GB RAM travados** — nunca junto de outro modelo (swap obrigatório); carga 1-3 min; **~10 tok/s decode, prefill ~8 tok/s** (gargalo), MTP aceite ~68% |
| **Variantes _XXk** | | | |
| `Gemma4_12B_128k` / `_MTP_128k` / `_Hauhau_128k` / `_Agentic_128k` | stock | 131072 | Gemma 4 12B @ 128K validada: 9487 MiB c/ mmproj (MTP: dentro do máx 192K) |
| `LFM2.5_8B_A1B_Hermes_128k` | stock | 131072 | 7063 MiB validado |
| `Ornith1.5_9B_MTP_128k` | stock | 131072 | 9475 MiB validado |
| `Qwen3.6_35B_General_96k` / `_Code_96k` / `_It_General_96k` / `_It_Reasoning_96k` / `_A3B_Hauhau_Aggressive_96k` | stock | 98304 | ub1024 (ub2048 não cabe c/ 96k); Code c/ ncmoe 28: 11577 MiB validado (apertado); demais ncmoe 32 — só com display idle |

Relevância para servir (uso agêntico/opencode): **alta** = Gemma4_12B_Agentic,
Qwen3.6_35B_Code/General, Qwen3.8_35B_Distill, Saluki27B, bonsai-27b,
Gemma4_12B; **média** =
LFM/Mellum, Xing, Ornith 35B, Hauhau, bonsai-pq2_0, It_*, Qwen3.8_27B_GSQ,
Strata (coder forte
mas prefill ~8 tok/s); **baixa** = Ornith 9B (×2).

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
- **Storage**: `du -sh models/*/` — SSD 220 GB; GGUFs órfãos (sem entry no
  config) são candidatos a remoção.
