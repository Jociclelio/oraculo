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
  modelo (12 entries: 10 stock + 1 Bonsai + 1 Xing).
  `models/models.ini` é HISTÓRICO desativado — nada o lê.
  **Convenção de contexto** (VRAM validada por carga real, display idle):
  entry SEM sufixo = **128k** (floor, `-c 131072`), viabilizado pelo KV
  quantizado `-ctk q5_1 -ctv iq4_nl` (regra 10); modelo que não alcança 128k
  = sufixo `_XXk` com o maior contexto validado. Com jogos no desktop
  (1,8+ GB VRAM) as entries de MoE híbrido podem OOM.
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
  - `engines/llama.cpp-pdcache/` — master ggml-org pinado no MESMO commit da
    imagem stock em uso + patch de prompt disk cache portado do fork
    qqkzlm (regra 9; a base `prism` original do fork tem prefill de MoE na
    CPU 20x mais lento — ver Dockerfile)
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
    `-ub 2048` nas entries Qwen3.6 128k + Ornith1.5_35B; `-ub 1024`
    no Xing (folga de VRAM). Motivo: com `-ncmoe`, cada
    ubatch relê os pesos dos experts na RAM; ubatch maior amortiza o custo.
    Nota: KV do Qwen3.6 é pequeno (só 10/41 camadas têm KV; 2 heads × 256 →
    ~10,6 KiB/tok em q8_0) — o gargalo é FFN de experts, não attention.
 8. **Geração de imagem (ComfyUI) e inferência de LLM dividem a mesma VRAM —
    liberação bidirecional automática.** O ComfyUI
    (yanwk/comfyui-boot, porta 8188 via gpu-shim; núcleo em 127.0.0.1:8189)
    roda com `--disable-smart-memory`: ao fim de cada geração os pesos
    voltam para RAM e a VRAM cai para o piso do runtime CUDA (~200-300 MiB
    de contexto + cuBLAS/cuDNN; `POST /free` com `free_memory:true` NÃO
    derruba esse piso — medido 2026-10-19; só matar o processo zeraria, ao
    custo de restart do torch ~10-20 s). No caminho de geração
    (Open WebUI/API; polling da UI nativa nunca descarrega), o gpu-shim
    (`comfyui/user-scripts/gpu-shim.py`, rodando dentro do container via
    pre-start.sh) avalia a VRAM livre e, se < 8 GiB, faz `POST /free` no
    ComfyUI (flush do caching allocator/fragmentação) e chama
    `GET :8081/unload` do llama-swap (síncrono) antes de repassar o request.
    `./manage.sh unload` usa o mesmo endpoint. Sem isso a carga do LLM ou
    do DiT dá OOM de compute buffer (`VRAM grow failed` no log do ComfyUI =
    DiT carregou com LLM residente). Desde 2026-10-18 o LLM costuma já estar
    DORMINDO no fluxo típico (regra 9, sleep aos 180 s de idle) — o unload
    fica como fallback para o uso < 3 min antes da imagem.
 9. **KV cache NÃO sobrevive ao unload/swap — RESOLVIDO via fork pdcache
    (2026-10-17) nas entries que o suportam.** O KV cache vive no processo do
    `llama-server`: quando o llama-swap remove o container `ls-*` (unload do
    gpu-shim, swap ou `ttl: 300`), a conversa é re-prefil inteira no retorno.
    O `--slot-save-path` + `/slots/0?action=save|restore` do stock **não
    funciona** em modelos **híbridos/recorrentes e SWA** — o formato não
    serializa os context checkpoints e o servidor cai em `forcing full prompt
    re-processing` (bug ggml-org/llama.cpp#28194, ainda aberto em 2026-10-17;
    medido aqui no LFM2.5: `cache_n: 0` com LCP similarity 1.000; o patch
    `--slot-save-checkpoints` do ky095n existe no issue mas exige orquestrar
    save antes do unload E restore depois da recarga — frágil com o
    `docker rm -f` do llama-swap).
    **Solução adotada**: engine `llama.cpp-pdcache` — master do ggml-org
    (commit pinado IGUAL ao da imagem stock em uso) + patch de prompt disk
    cache portado do fork qqkzlm/llama-cpp-prompt-disk-cache (v0.1.0, commit
    `451db3b`; `engines/llama.cpp-pdcache/` + macro `docker-pdcache`):
    snapshots COMPLETOS `.centry` (tokens + estado de sequência inteiro, com
    guard de fingerprint/ctx/FA/tipos KV/build) escritos atomicamente em
    disco no fim do slot e restaurados automaticamente no próximo request
    após o (re)start — sem orquestração no gpu-shim, indiferente a SIGKILL.
    Cache em bind mount `./data/llama-pdcache` (compartilhado entre entries —
    guard descarta entradas incompatíveis). Medição do autor (Qwen3.6-35B,
    prompt agêntico 40k): prefill 151 s → 1,35 s no hit. Custo residual:
    recarga fria de pesos (10-30 s) + leitura/restauro do snapshot (~2 s, só
    no primeiro request pós-unload).
    **Por que NÃO a imagem do próprio fork**: a linhagem `prism` (PrismML)
    tem o caminho de MoE com experts na CPU NÃO otimizado — medido
    2026-10-17: prefill 21k tokens a 35→18 tok/s (vs 800 tok/s no stock)
    com -ncmoe 31 + --load-mode none, com e sem o cache ligado; o mesmo
    collapse ocorre na engine prismml 84445367f. Portanto o patch foi
    portado para o master (conflitos resolvidos à mão em arg.cpp,
    CMakeLists.txt e server-context.cpp — hunks de prefix-only descartados,
    modo desabilitado por ser inseguro em híbridos). **Validado aqui em
    2026-10-18** (Qwen3.6_35B_Code, prompt 21k, qwen35moe/GDN): após
    `docker rm -f` + re-request, `cache_n` 21213/21217 (99,98%), `prompt_n` 4,
    prefill ~0,5 s (era 33 s); snapshot `.centry` 638 MiB (escrita 730 ms,
    leitura 765 ms, restore p/ GPU 48 ms); prefill da engine no 1º request
    642 tok/s (paridade com o stock). **Rollout completo no mesmo dia**:
    todas as 12 entries base-stock usam o macro `docker-pdcache` (bonsai e
    Xing ficam nas engines dedicadas — o patch é contra o master ggml-org).
    **Correção 2026-10-18 (crashes "modelo não responde")**: o caminho de
    prompt cache (RAM e disco) serializa o estado completo da conversa
    (~47 KiB/token → 1 GB @ 21k, ~6 GB @ 128k) e o `store()` de disco fazia
    uma SEGUNDA cópia integral — com os pesos fixados na RAM (regra 2) e
    ~3-4 GB disponíveis, conversa longa = OOM killer matando o llama-server
    no meio do streaming (`read error during body copy` + `upstream process
    exited unexpectedly` no log do llama-swap; 71 ocorrências desde 2026-10-11,
    ANTES do pdcache — o spike do `prompt_save` de RAM com `--cache-ram 2048`
    já causava isso). Correções no patch: `store()` com `shared_ptr` (sem
    2ª cópia no caminho de release), guarda de `MemAvailable` antes de
    alocar/ler snapshots (store de RAM, store de disco e restore de disco —
    degrada para re-prefill com WRN no log em vez de OOM) e `--cache-ram`
    2048→1024 no macro.
    **Correção 2026-10-18b (crash multimodal)**: entradas `.centry` achataam
    o prompt para texto puro (`get_text_tokens()`) e perdem o mapa de mídia —
    restaurar uma conversa que tinha imagem/áudio quebrava o bookkeeping de
    posições e abortava o servidor (`GGML_ASSERT(has_mtmd)` em
    `push_back_placeholder`; o vazamento: turnos com mídia não criam
    checkpoints novos, mas o store carregava os antigos de turnos de texto).
    ATENÇÃO à semântica: `server_tokens.has_mtmd` fica `true` para TODO
    modelo multimodal (mmproj carregado) mesmo em requests só de texto
    (`slot.prompt.tokens.has_mtmd = mctx != nullptr`) — o teste correto de
    "mídia de verdade" é `find_next_media_chunk(0).first != nullptr`.
    Correção: prompts com mídia real não entram no cache de disco (store e
    lookup) — conversas com imagem/áudio re-prefill (o prompt cache de RAM
    as cobre na mesma sessão); conversas de texto em modelos multimodais
    continuam 100% cacheadas. Nota: o store é assíncrono pós-resposta —
    unload em menos de ~1-2 s após o fim da resposta pode perder o snapshot
    do turno (writer morto pelo `rm -f`; perda benigna, o próximo turno
    regrava). No fluxo real (gpu-shim: geração de imagem leva dezenas de
    segundos) não ocorre.
    **Sleep em vez de derrubar (2026-10-18c)**: macro pdcache com
    `--sleep-idle-seconds 180` e `ttl: 1800` nas 12 entries. Semântica do
    sleep no master: após 180 s de idle o servidor destrói contexto/modelo/KV
    E os pesos da RAM (`destroy()` — mantém só o processo/queue/CUDA-runtime,
    VRAM → ~900 MiB de display) e **acorda sozinho** no próximo request
    (`wait_until_no_sleep`), recarregando o modelo — sem churn de container,
    sem corrida com o writer do snapshot, e o /health continua 200 durante o
    sono (llama-swap não o derruba antes do ttl). O L1 de RAM do prompt cache
    NÃO sobrevive ao sleep (o disco cobre). Medido no Code (MoE 35B): wake +
    resposta completa em 31 s com `cache_n` 21213/21217 — o dominante segue
    sendo a releitura dos pesos do NVMe; para modelos com page cache quente
    (Gemma/bonsai/1B) o wake cai para ~2-4 s. Trade-off assumido: follow-up
    instantâneo só na janela de 0-180 s de idle (antes eram 300 s de ttl);
    gpu-shim continua descarregando se o modelo estiver acordado.
 10. **KV cache quantizado em TODAS as entries: `-ctk q5_1 -ctv q5_1`**
    (nos macros, exige `-fa on` — já padrão) e SEMPRE com tipo ÚNICO K=V.
    **K e V com tipos diferentes (ex.: q5_1/iq4_nl) destrói a performance
    nos híbridos GDN/SWA no stock** (medido 2026-10-15, Hauhau/qwen35moe:
    prefill 1313→23 tok/s, decode 34→7,5 tok/s, degrada com o contexto —
    validação de VRAM não pega isso; sempre gerar tokens suficientes).
    O fork Xing rejeita K≠V explicitamente. Padrão 2026-10-15 junto da
    subida do floor de contexto para 128k: q5_1 (6 bpw) ocupa ~0,71× do
    q8_0 (8,5), o que compensa os 2× tokens do 128k. Sempre que apertar
    VRAM, a alavanca é subir `-ncmoe` (mais experts na RAM, ~0,5 GB/camada
    no Qwen3.6), não voltar o KV para q8_0.
    **EXCEÇÃO fork PrismML (2026-10-20)**: no fork, o KV q5_1 NÃO tem
    caminho rápido de flash attention (issue PrismML #191; nosso build
    não define `-DGGML_CUDA_FA_ALL_QUANTS=ON`) — degrada com o contexto
    (medido no 9B @4k: decode 12,6 vs 77,9 tok/s com f16; prefill 41 vs
    1723). As entries bonsai SOBRESCREVEM: q4_0 nos 27B (rápido E menor
    que o q5_1 — mantém o floor 128k), bf16 nos 9B (teto de performance;
    @192k — o nativo 256k não cabe e 224k fica sem margem).

---

## Modelos (RTX 3060 12 GB — medições e2e)

VRAM = pico nvidia-smi (total, incl. ~890 MiB do display) na carga real @
128k com KV `q5_1`/`q5_1` (validação 2026-10-15, revalidado após a troca
iq4_nl→q5_1 — ver regra 10). tok/s foram medidos no
ctx 64k anterior (decode não muda com o ctx; prefill por token idêntico).

| Entry | Engine | Ctx | Notas / tok/s medido |
|-------|--------|-----|----------------------|
| `Gemma4_12B` | stock | 131072 | Gemma 4 12B IT QAT; multimodal (visão + **áudio nativo** — mmproj único com os dois encoders, `clip.has_audio_encoder=true`); VRAM 9259 MiB |
| `LFM2.5_24B_A2B` | stock | 131072 | LiquidAI raciocínio puro agêntico, MoE 24B/2,45B (64 experts top-4); ncmoe 20 + `--load-mode none` + ub2048; **~45 tok/s, prefill ~1900 tok/s**; VRAM 10516 MiB; sampling temp 0.1 / top-k 50 / rep 1.05; sem MTP (draft DSpark não publicado) |
| `LFM2.5_24B_A2B_IQ2_M` | stock | 131072 | unsloth UD IQ2_M (7,5 GB) — a mesma LFM2.5 em **100% GPU** (sem `--load-mode none`/`-ncmoe`); **decode ~76-103 tok/s curto / 26 tok/s @130k, prefill 21k ~3589 tok/s / 130k ~2172 tok/s**; 128k validado de ponta a ponta (VRAM 9940 MiB @130k, ~2,3 GB de folga); sem MTP; sampling temp 0.1 / top-k 50 / rep 1.05 (2026-10-19) |
| `MiniCPM-V_4.7_35B` | stock | 131072 | MiniCPM-V 4.7 35B-A3B multimodal Q4_K_M + mmproj f16 (openbmb `-gguf`); backbone Qwen3.6 (arch qwen35moe, 256 experts/8 ativos, GDN); **SEM MTP** (header declara nextn=1 mas sem tensors; draft DSpark testado e descartado: aceitação ~10%, decode 9,5 tok/s, buffer ~3,9 GB não cabe — GGUF do draft guardado em `models/MiniCPM-V-4.7-35B-A3B-DSpark/`); ncmoe 32 + `--load-mode none` + ub2048; requer llama.cpp ≥ PR #29416 (imagem stock atualizada p/ build 11561, fingerprint `b11561-e937b17a2`); **~32-35 tok/s, prefill ~1040 tok/s**; VRAM 9488 MiB; visão validada |
| `MiniCPM-V_4.7_1B` | stock | 131072 | MiniCPM-V 4.7 1B multimodal Q4_K_M + mmproj f16 (openbmb `-gguf`); variante edge DENSA da série (arch qwen35, sem experts); mesmo visor LLaVA-UHD v4 da 35B; SEM MTP (draft DSpark disponível no repo mas não instalado — precedente da 35B: aceitação ~10%); **decode ~200 tok/s, prefill ~8000-8500 tok/s**; visão validada (2026-10-16) |
| `Qwen3.6_35B_General` | stock | 131072 | thinking + head MTP; ncmoe 33; ub2048; aceitação ~82-93%; VRAM 11172 MiB (c/ mmproj) |
| `Qwen3.6_35B_Code` | stock | 131072 | thinking + head MTP; ncmoe 31; **~27 tok/s, aceitação 93%** — MoE híbrido padrão; ub1024: prefill ~750 tok/s; VRAM 11426 MiB (c/ mmproj, a mais apertada) |
| `Qwen3.6_35B_It_General` / `_It_Reasoning` | stock | 131072 | Instruct (sem/temp thinking); ncmoe 33; ub2048; VRAM 11172/11172 MiB (c/ mmproj) |
| `Qwen3.6_35B_A3B_Hauhau_Aggressive` | stock | 131072 | Uncensored Aggressive, multimodal; ncmoe 29; ub2048 + `--load-mode none`; **prefill ~1150 tok/s, decode ~39 tok/s**; VRAM 10891 MiB; SEM MTP (GGUF sem tensors nextn — spec inaplicável; `--moe-cache-mib` testado e rejeitado: decode -21%) |
| `Ornith1.5_35B_MTP` | stock | 131072 | agêntico (APEX Compact), ncmoe 29 + `--load-mode none` (faltava — regra 2); ub2048: prefill ~990 tok/s; VRAM 11538 MiB (c/ mmproj, visão confirmada — Baseten/Atomic Chat/repo mudler); aceitação ~0,80 |
| `Ornith1.5_9B` | stock | 131072 | Ornith-1.5-9B Q4_K_M + mmproj BF16 (ornith-ai); variante edge DENSA da família (arch qwen35), raciocínio agêntico `<think/tool_call>`; head MTP embutida (nextn=1) → draft-mtp self-draft n=2; **decode ~48-52 tok/s, prefill ~1430-1580 tok/s, aceitação ~0,53-0,69**; VRAM 9862 MiB (2026-10-16) |
| `Qwen3.5_9B_HauhauCS` | stock | 131072 | Qwen3.5-9B-Uncensored-HauhauCS-Aggressive Q4_K_M + mmproj BF16; denso (arch qwen35, no lugar da Ornith1.5_9B_Uncensored removida 2026-10-19); **SEM MTP** (header sem nextn); **decode ~52 tok/s, prefill 21k ~1671 tok/s**; VRAM 9088 MiB; visão carregada (2026-10-19) |
| `MiMo2.6_9B` | stock | 131072 | MiMo-V2.6-Distill-Qwen-9B (XiaomiMiMo, distill em base Qwen3.5; arch qwen35, denso) Q4_K_M bartowski + mmproj f16 (ggml-org oficial só Q8_0 9,5 GB — não cabe com floor 128k); reasoning separado; **SEM MTP** (header sem nextn); **decode ~47-51 tok/s, prefill ~1800 tok/s @2,6k**; VRAM 9510 MiB; visão validada; sampling temp 0.6 / top-p 0.95 / top-k 20 (generation_config oficial) (2026-10-20) |
| `bonsai-27b` | PrismML | 131072 | PTQ1_0 + mmproj (visão validada); **KV q4_0 (2026-10-20)** — o q5_1 dos macros NÃO tem caminho rápido de FA no fork PrismML (issue PrismML #191; build sem `-DGGML_CUDA_FA_ALL_QUANTS=ON`): degrada 30-40× (decode 12,6→78 tok/s @4k no 9B com f16). Com q4_0: **decode ~23 tok/s, prefill ~480 tok/s estável @21k+**; VRAM 10700 MiB |
| `bonsai-27b-heretic` | PrismML | 131072 | finetune Uncensored "Heretic" (OS-Software) do Bonsai 2 acima; PTQ1_0 + mmproj Q8_0, mesma engine pinada e MESMO fix de KV q4_0: **decode ~23 tok/s, prefill ~464 tok/s @4k**; VRAM 10590 MiB; sem pdcache/sleep (patch só no master ggml-org) (2026-10-20) |
| `bonsai-9b` | PrismML | 196608 | Bonsai 2 9B (variante edge, denso); PTQ1_0 + mmproj Q8_0, mesma engine PrismML pinada; **KV bf16 @192k (2026-10-20 — q5_1 lento no fork, issue PrismML #191; f256k nativo não cabe, 224k só com ~480 MiB de folga)**: decode ~71 tok/s @4k (~48 @21k), prefill ~1600 tok/s; VRAM 10532 MiB; visão validada; SEM MTP/DFlash (drafts no repo HF não baixados) |
| `bonsai-9b-uncensored` | PrismML | 196608 | Bonsai 2 9B + LoRA uncensored AtomicChat (rank-1, 3,2 MB, `--lora-scaled :1` — remove direção de recusa no grafo; base byte-idêntico; custo ~4,3 MMLU); MESMOS GGUFs/engine/KV bf16 @192k do `bonsai-9b`; VRAM 10672 MiB; aplicação validada por logprobs distintos vs base; modelo thinking consome muitos tokens de raciocínio (~900 p/ pergunta simples) (2026-10-20) |
| `Xing4.0_29B_A4B` | Xing | 131072 | MoE 29B/4B + MLA + mHC; `--load-mode none` + ncmoe 27; ub1024; **KV q5_1/q5_1 (regra 10)**; ~12,5 tok/s @ 64k; VRAM 10850 MiB |

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
> `engines/strata/README.md`. **Variantes de contexto `_96k`/`_128k`
> removidas em 2026-10-15** (sem apagar GGUFs): o floor subiu para 128k em
> todas as entries base com o KV quantizado q5_1/iq4_nl — as variantes
> ficaram redundantes (mesmos GGUFs, mesma receita). **Qwen3.8-27B-GSQ-RCO
> IQ2_XS-mtp** (`Qwen3.8_27B_GSQ_IQ2_XS_64k`) instalado e removido no mesmo
> dia (GGUF 8,2 GB apagado): não atende os requisitos mínimos — não alcança
> o floor 128k (denso híbrido GDN+SSM, KV/token alto: 96k nem carrega),
> prefill ~42 tok/s (ops GDN serializam CPU↔GPU), margem de VRAM ~550 MiB
> e decode dependente do draft-mtp (~7 tok/s sem ele).
> **Qwen3.8-35B-A3B-Distill** (`Qwen3.8_35B_Distill`) removida em 2026-10-16
> (GGUFs apagados, ~22 GB liberados): redundante com o zoológico Qwen3.6
> (mesma arch qwen35moe, aceitação MTP ~0,62 inferior) e uma das entries
> mais pesadas em VRAM/disco.

Relevância para servir (uso agêntico/opencode): **alta** = Qwen3.6_35B_Code/General,
bonsai-27b,
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
- **Modelo some/no responde, log do llama-swap com `read error during body
  copy` + `upstream process exited unexpectedly`**: processo morto por RAM —
  snapshot do prompt cache maior que a memória disponível (ver regra 9,
  correção de 2026-10-18 com guarda de MemAvailable). Confirmar com
  `docker events` (attr `oomKilled=true`) e `free -g`; mitigar com
  `--cache-ram` menor ou conversas mais curtas.
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
