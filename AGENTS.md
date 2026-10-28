# oraculo — instruções para agentes

Servidor local de LLMs: **llama-swap** (proxy multi-engine em `127.0.0.1:8081`,
sobe um container Docker efêmero de llama.cpp por modelo sob demanda) +
**Open WebUI** (`:8080`) + Open Terminal (`:8000`), SearXNG (`:8888`), OpenWa
(`:2785`). Hardware alvo: **RTX 3060 12 GB** (GPU **compartilhada** com o
desktop pessoal) + 32 GB RAM + NVMe.

**GPU unlock (2026-10-24)**: kmod `gpu-unlock` 1.0.0 (Zagitta/gpu-unlock,
pacotes Arch `gpu-unlock-dkms` + `gpu-unlock-firmware` em `/home/jocic/gpu-unlock`)
habilita a taxa plena de BF16 tensor da GA106 (estilo profissional) ANTES do
driver NVIDIA bindar (roda no initramfs; opt-in via cmdline
`gpu_unlock.targets=all` na entry systemd-boot `cachyos-unlock.conf`). Medido:
BF16 GEMM 8192³ FP32-accum 47 TFLOPS (stock travado ~25 — metade do FP16).
Ganho esperado: prefill de modelos DENSOS (Gemma4_12B, LFM IQ2_M, MiniCPM 1B,
bonsai-9b) e ComfyUI/DiT; NÃO muda prefill das entries MoE `-ncmoe` (gargalo
é streaming de pesos da RAM, regra 7) nem decode (banda de memória).
ATENÇÃO: o drop-in `/etc/mkinitcpio.conf.d/zz-gpu-unlock.conf` foi editado
localmente para remover o sufixo `?` do nome do módulo — com `?`, o
systemd-modules-load do initramfs falha a achar `gpu_unlock?` (hook `systemd`
do mkinitcpio escreve MODULES verbatim) e o unlock não roda. Se atualizar o
pacote, reaplicar o sed. `default @saved` no loader.conf memoriza a entry do
boot anterior.

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
  modelo (11 entries: 10 stock + 1 Bonsai).
  `models/models.ini` é HISTÓRICO desativado — nada o lê.
  **Convenção de contexto** (VRAM validada por carga real, display idle):
  entry SEM sufixo = **128k** (floor, `-c 131072`), viabilizado pelo KV
  quantizado `-ctk q4_0 -ctv q4_0` (regra 10; q5_1 até 2026-10-26); modelo que não alcança 128k
  é REMOVIDO do zoo (política 2026-10-26; precedente: K2-Horizon 40k).
  Com jogos no desktop
  (1,8+ GB VRAM) as entries de MoE híbrido podem OOM.
- Macros no config: `docker-stock` (imagem oficial
  `ghcr.io/ggml-org/llama.cpp:full-cuda`, entrypoint `/app/llama-server`),
  `docker-prismml` (imagem local, entrypoint
  `/usr/local/bin/llama-server`), `docker-stop`.
- **O llama-swap NÃO executa o cmd via shell (shlex)**: nada de `;`, pipes ou
  redirects no `cmd` — um único comando por entry.
- Engines dedicadas vivem em `engines/<fork>/` (Dockerfile + build.sh),
  clonando o fork **pinado em commit** (o build falha se HEAD ≠ pin):
  - `engines/llama.cpp-prismml/` — commit `84445367f` (branch `prism`)
  - `engines/llama.cpp-pdcache/` — master ggml-org pinado no MESMO commit da
    imagem stock em uso + patch de prompt disk cache portado do fork
    qqkzlm (regra 9; a base `prism` original do fork tem prefill de MoE na
    CPU 20x mais lento — ver Dockerfile)
  - `engines/llama.cpp-bonsai-ada/` — commit `2cadbfb64` (branch
    `bonsai-q8-product` de professorpalmer/llama.cpp-ada-ternary; =
    PrismML `adfffbe` + a pilha de 71 patches do projeto
    bonsai-ada-surgery). Supersetch da prismml: KV tiered
    (`--kv-vram-cells`), FA lê q4_0/q8_0/q3_0 K/V in place, MTP
    self-draft + lookup n-gram, harness-proofing de reasoning.
  - Verificar engine em runtime: `system_fingerprint` nos responses
    (`b1-8444536` PrismML, `b1-2cadbfb` bonsai-ada).
- Instalar modelo novo: guia em `models/MODELS_INSTALL.md`
  (`hf download ... --local-dir models/<Dir>` + entry no config + restart).

---

## Regras duras (erros que já custaram horas)

1. **NUNCA servir Bonsai 2 com a imagem stock.**
   - Bonsai (ternários PTQ1_0/PQ2_0): kernels só no fork PrismML; stock recusa
     ou carrega como Q2_0 legacy gerando lixo.
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
    ubatch maior amortiza a re-leitura de experts; o batch é irrelevante.**
    Medido 2026-10-11 (Qwen3.6_35B_Code, prompt 5,6k tok, display idle):
    ub512→400 tok/s; ub1024→594; ub2048→865-909; ub4096 abortava a carga.
    Motivo: com `-ncmoe`, cada ubatch relê os pesos dos experts na RAM.
    Nota: KV do Qwen3.6 é pequeno (só 10/41 camadas têm KV; 2 heads × 256 →
    ~10,6 KiB/tok em q8_0) — o gargalo é FFN de experts, não attention.
    **Calibração automática 2026-10-26** (`benchmarks/calibrate.sh`, prompt
    8k e2e, build 11804, gpu-unlock ATIVO — números absolutos ~+50% vs
    2026-10-11): o ubatch domina e o batch não (b4096 vs b8192 no mesmo ub
    = ruído; `-b 8192` continua sem ajudar). Sem draft: ub1024→~1016-1065,
    ub2048→~1281-1385, ub4096→~1300-1627 (Flint 1305, MiniCPM 1627, Qwen
    sem draft 1585). COM draft MTP (Qwen Code): ub2048→1288 OK na imagem
    stock (11849 MiB) mas **estoura na receita completa de serving**
    (pdcache/sleep/checkpoints): `cublasGemmEx internal operation failed`
    no 1º request, reproduzível — a receita completa tem ~350-400 MiB a
    mais de pegada. **Lições**: (a) calibrar SEMPRE com `CAL_EXTRA_FLAGS`
    da receita real e validar o vencedor com carga no llama-swap antes de
    aplicar; (b) sem draft MTP, `ub 4096` cabe e vence. Aplicado
    2026-10-26: `ub 4096` em Flint_40B (prefill ~1097→1300, VRAM serving
    10567 MiB) e MiniCPM-V_4.7_35B (~1383→1619, VRAM 10359 MiB);
    Qwen3.6_35B_Code MANTÉM `ub 1024` (ub2048 + draft não cabe nesta
    build);
 8. **Geração de imagem (ComfyUI) e inferência de LLM dividem a mesma VRAM —
    liberação bidirecional automática.** O ComfyUI
    (yanwk/comfyui-boot, porta 8188 via gpu-shim; núcleo em 127.0.0.1:8189)
    roda com `--disable-smart-memory`: ao fim de cada geração os pesos
    voltam para RAM e a VRAM cai para o piso do runtime CUDA (~200-300 MiB
    de contexto + cuBLAS/cuDNN; `POST /free` com `free_memory:true` NÃO
    derruba esse piso — medido 2026-10-19; só matar o processo zeraria, ao
    custo de restart do torch ~10-20 s). No caminho de geração
    (Open WebUI/API e, desde 2026-10-20, o POST /prompt da UI nativa no
    navegador; polling GET da UI nunca descarrega), o gpu-shim
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
 10. **KV cache quantizado em TODAS as entries: `-ctk q4_0 -ctv q4_0`**
    (nos macros, desde 2026-10-27; exige `-fa on` — já padrão) e SEMPRE
    com tipo ÚNICO K=V. **K e V com tipos diferentes (ex.: q5_1/iq4_nl)
    destrói a performance nos híbridos GDN/SWA no stock** (medido
    2026-10-15, Hauhau/qwen35moe: prefill 1313→23 tok/s, decode 34→7,5
    tok/s, degrada com o contexto — validação de VRAM não pega isso;
    sempre gerar tokens suficientes). O fork Xing rejeita K≠V
    explicitamente (aceita q4_0/q4_0 — validado 2026-10-27).
    **HISTÓRICO / MUDANÇA 2026-10-27**: o default desde 2026-10-15 era
    q5_1/q5_1 (6 bpw, ~0,71× do q8_0 — compensava os 2× tokens do 128k).
    A bateria e2e de decode×contexto (24 entries, `results/ctxsweep/`)
    revelou que **o q5_1 NÃO tem kernel de flash attention dedicado**
    (só f16/bf16/q4_0/q8_0 têm) e cai no caminho genérico lento:
    decode @130k foi **2,3× menor** que q8_0 no MiniCPM 1B, **2,26×** no
    MiMo 9B, **1,27×** na Gemma4 12B e **1,19×** no Qwen3.6 (A/B controlado,
    256 tok/pt, temp 0) — e o q5_1 perde **+9-18% até em ctx vazio**.
    O mesmo sintoma no fork PrismML (issue PrismML #191, 2026-10-20) não
    era exceção: era o mesmo bug de cobertura de kernels.
    **q4_0 ≈ q8_0 em velocidade** com o MENOR footprint (0,53× do q8_0,
    0,73× do q5_1) → default geral. **q8_0** é override opcional onde a
    precisão do KV importa e houver folga (+41% de KV vs q4_0; validar
    carga por entry). Sempre que apertar VRAM, a alavanca é subir
    `-ncmoe` (mais experts na RAM, ~0,5 GB/camada no Qwen3.6), não mudar
    o KV. EXCEÇÕES bonsai no fork PrismML: bf16 nos 9B (medido — teto de
    performance; @192k), q4_0 nos 27B (= novo default, validado antes).

---

## Modelos (RTX 3060 12 GB — medições e2e)

VRAM = pico nvidia-smi (total, incl. ~890 MiB do display) na carga real @
128k com o KV do macro vigente na validação (q5_1/q5_1 até 2026-10-26;
**q4_0/q4_0 desde 2026-10-27** — ver regra 10; q4_0 usa ~73% do KV do
q5_1, então as validações de VRAM continuam valendo com folga).
**Números "pós-unlock 2026-10-26"**: decode (200 tok) e prefill @2k
medidos e2e no serving com gpu-unlock ATIVO (BF16 47 TFLOPS) — não
comparáveis aos anteriores; decode @ctx longo tende a cair nos híbridos
(ver séries do `benchmarks/bench.sh` e a bateria `results/ctxsweep/`
de 2026-10-27, que também reescreveu a regra 10 — q5_1 era lento por
falta de kernel FA dedicado).

| Entry | Engine | Ctx | Notas / tok/s medido |
|-------|--------|-----|----------------------|
| `Gemma4_12B` | stock | 131072 | Gemma 4 12B IT QAT; multimodal (visão + **áudio nativo** — mmproj único com os dois encoders, `clip.has_audio_encoder=true`); **decode ~40 tok/s, prefill ~1250 tok/s** (pós-unlock 2026-10-26); VRAM 9314 MiB; thinking consome tokens |
| `LFM2.5_24B_A2B` | stock | 131072 | LiquidAI raciocínio puro agêntico, MoE 24B/2,45B (64 experts top-4); ncmoe 20 + `--load-mode none` + ub2048; **decode ~46 tok/s, prefill ~1640 tok/s** (pós-unlock 2026-10-26); VRAM 10602 MiB; sampling temp 0.1 / top-k 50 / rep 1.05; sem MTP (draft DSpark não publicado) |
| `LFM2.5_24B_A2B_IQ2_M` | stock | 131072 | unsloth UD IQ2_M (7,5 GB) — a mesma LFM2.5 em **100% GPU** (sem `--load-mode none`/`-ncmoe`); **decode ~106 tok/s, prefill ~2960 tok/s** (pós-unlock 2026-10-26 — o mais rápido do zoo); 128k validado de ponta a ponta (VRAM 9940 MiB @130k pré-unlock); sem MTP; sampling temp 0.1 / top-k 50 / rep 1.05 |
| `LFM2.5_24B_A2B_Uncensored` | stock | 131072 | MESMA receita da `LFM2.5_24B_A2B` + LoRA rank-1 AtomicChat (24 MB, `--lora-scaled :1.75` — blocos 14-39: mixers + ffn_down dos 64 experts; sites verificados em CPU: 52/52 no Q4_K_M; autor: refusals 96,3%→1,2%, MMLU 64,4→65,6); **validado 2026-10-28**: 2/2 probes sem recusa (lockpicking; sanidade harmless OK), reasoning intacto, decode ~29-31 tok/s no serving (sem A/B controlado vs base); VRAM ~10600 MiB |
| `MiniCPM-V_4.7_35B` | stock | 131072 | MiniCPM-V 4.7 35B-A3B multimodal Q4_K_M + mmproj f16 (openbmb `-gguf`); backbone Qwen3.6 (arch qwen35moe, 256 experts/8 ativos, GDN); **SEM MTP** (header declara nextn=1 mas sem tensors; draft DSpark testado e descartado: aceitação ~10%, decode 9,5 tok/s, buffer ~3,9 GB não cabe — GGUF do draft APAGADO em 2026-10-26, re-baixável via MODELS_INSTALL.md); ncmoe 32 + `--load-mode none` + **ub 4096** (calibração 2026-10-26: prefill ~1383→1619 tok/s; VRAM serving 10359 MiB); requer llama.cpp ≥ PR #29416 (imagem stock atualizada p/ build 11561, fingerprint `b11561-e937b17a2`); **~32-35 tok/s, prefill ~1040→~1600 tok/s**; visão validada |
| `MiniCPM-V_4.7_35B_Uncensored` | stock | 131072 | MESMA receita da `MiniCPM-V_4.7_35B` + LoRA rank-1 AtomicChat (106 MB, `--lora-scaled :1.0` — 120 sites: attn/linear outputs + ffn_down dos 256 experts + 40 shared experts; sites verificados em CPU: 120/120 no Q4_K_M; embedding NÃO editado — o vision projector copia linhas dele; autor: refusals 96,3%→0%, MMLU +0,25); **validado 2026-10-28**: 2/2 probes sem recusa (lockpicking; harmless OK), thinking intacto; VRAM ~10455 MiB c/ display |
| `MiniCPM-V_4.7_1B` | stock | 131072 | MiniCPM-V 4.7 1B multimodal (openbmb `-gguf`); variante edge DENSA da série (arch qwen35, sem experts); mesmo visor LLaVA-UHD v4 da 35B; SEM MTP; **decode ~248 tok/s, prefill ~10400 tok/s** (pós-unlock 2026-10-26 — prefill recorde do zoo); visão validada (2026-10-16) |
| `Qwen3.6_35B_A3B` | stock | 131072 | thinking + head MTP; **tuning de planura 2026-10-28** (probe de profundidade, `benchmarks/probe_depth.py`): `--spec-draft-n-max 3 --spec-draft-p-min 0.5` + `-ncmoe 32` — decode ~38-42 tok/s curto, **~31,5 @130k** (era 23 com n-max 2/p-min 0/ncmoe 33; planura 0,57→0,76, acc@130k 0,80→0,92), prefill ~980-1094 curto / ~624 @130k; VRAM ~11190 MiB (c/ mmproj); IZ 36-58 em toda a janela (antes caía a 23 = "não usável"); ngram empilhado ao MTP testado e REJEITADO (acc 0,60) — única entry do Qwen3.6 desde 2026-10-26 (Code/It_* removidas; uncensored na entry Hauhau) |
| `Qwen3.6_35B_A3B_Hauhau_Aggressive` | stock | 131072 | Uncensored Aggressive, multimodal; ncmoe 29; ub2048 + `--load-mode none`; **decode ~41 tok/s, prefill ~1100 tok/s** (pós-unlock 2026-10-26); VRAM 11240 MiB; SEM MTP (GGUF sem tensors nextn — spec inaplicável; `--moe-cache-mib` testado e rejeitado: decode -21%) |
| `Ornith1.5_35B_MTP` | stock | 131072 | agêntico (APEX Compact), ncmoe 29 + `--load-mode none`; ub2048; MTP self-draft (aceitação ~38% pós-unlock); **decode ~32 tok/s, prefill ~1140 tok/s** (2026-10-26); VRAM 11564 MiB (c/ mmproj, visão confirmada — Baseten/Atomic Chat/repo mudler) |
| `Nemotron3.5_Bolt_74B` | stock | 131072 | NVIDIA Nemotron-3.5-Bolt 74B-A9B (arch `nemotron_h_moe`: 88 blocos híbridos Mamba/atenção; KV pequeno → 128k ok); GGUF "24GB" + mmproj; **ncmoe 74/88** (o 32 original OOMava — experts de ~56 blocos ficavam na GPU) + `--no-mmproj-offload` (mmproj na CPU, -1,7 GB); **SEM draft** (DFlash medido c/ aceitação ~27% → decode 9,2 tok/s; sem draft **decode ~19 tok/s, prefill ~560 tok/s**; GGUF do draft (952 MB) em disco p/ reteste); ub 2048; **VRAM ~11060 MiB** (~1,2 GB de folga); temp 1.0 / top-p 0.95; visão carregada, não testada (2026-10-26) |
| `SageA1.5_35B` | stock | 131072 | InternScience Sage-A1.5 35B-A3B multimodal (arch qwen3_5_moe); GGUF oficial Q4_K_M + mmproj; ncmoe 31 + `--load-mode none` + ub 2048; thinking; **decode ~34 tok/s, prefill ~1000 tok/s**; VRAM 9849 MiB; sampling temp 1.0 / top-p 0.95 / top-k 20 / presence 1.5; visão carregada, não testada; carga validada (2026-10-26) |
| `Apodex1.1_35B` | stock | 131072 | Apodex 1.1 mini 35B-A3B multimodal (arch qwen3_5_moe; GGUF abenzerps — oficial publica NVFP4, sem GGUF); ncmoe 31; **decode ~39 tok/s, prefill ~940 tok/s** (mais rápido que o Qwen3.6 35B); VRAM 9849 MiB; temp 1.0 / top-k 20 / top-p 0.95 (2026-10-26) |
| `NexN2.5_35B` | stock | 131072 | Nex-N2.5 mini 35B multimodal (arch qwen3_5_moe, GGUF bartowski + mmproj f16); ncmoe 31; **decode ~36 tok/s, prefill ~900 tok/s**; VRAM 10609 MiB; temp 0.7 / top-p 0.95 / top-k 40; thinking via reasoning_effort no template (2026-10-26) |
| `BigBangv1_35B` | stock | 131072 | BigBang v1 35B-A3B multimodal (arch qwen3_5_moe, GGUF mradermacher + mmproj f16); ncmoe 31; **decode ~37 tok/s, prefill ~970 tok/s**; VRAM 10625 MiB; temp 1.0 / top-k 20 / top-p 0.95 (2026-10-26) |
| `Ornith1.5_9B` | stock | 131072 | Ornith-1.5-9B Q4_K_M + mmproj BF16 (ornith-ai); variante edge DENSA da família (arch qwen35), raciocínio agêntico `<think/tool_call>`; head MTP embutida (nextn=1) → draft-mtp self-draft n=2 (aceitação ~50% pós-unlock); **decode ~58 tok/s, prefill ~1600 tok/s** (2026-10-26); VRAM 10244 MiB |
| `Qwen3.5_9B_HauhauCS` | stock | 131072 | Qwen3.5-9B-Uncensored-HauhauCS-Aggressive Q4_K_M + mmproj BF16; denso (arch qwen35, no lugar da Ornith1.5_9B_Uncensored removida 2026-10-19); **SEM MTP** (header sem nextn); **decode ~55 tok/s, prefill ~1800 tok/s** (pós-unlock 2026-10-26); VRAM 10255 MiB; visão carregada |
| `MiMo2.6_9B` | stock | 131072 | MiMo-V2.6-Distill-Qwen-9B (XiaomiMiMo, distill em base Qwen3.5; arch qwen35, denso) Q4_K_M bartowski + mmproj f16; reasoning separado; **SEM MTP** (header sem nextn); **decode ~53 tok/s, prefill ~1615 tok/s** (pós-unlock 2026-10-26); VRAM 9508 MiB; visão validada; sampling temp 0.6 / top-p 0.95 / top-k 20 (generation_config oficial) |
| `Flint_40B_A2.5B` | stock | 131072 | Recursive Flint (RecursiveSI) MoE 40B/2,5B agêntico de código (arch `flint`: 49 camadas = 2 densas + 47 MoE, 256 experts top-6 + shared, 35 SWA janela 513 + 14 full-attention); **texto puro — sem mmproj, SEM MTP/draft**; GGUF oficial ggml-org Q4_K_M (23,4 GB); ncmoe 38 + `--load-mode none` + **ub 4096** (calibração 2026-10-26: prefill ~1097→1300 tok/s; VRAM serving 10567 MiB; sem draft o ub4096 cabe); requer build ≥ PR ggml-org#30928 (imagem stock atualizada p/ 11804/c7fc50941 + pdcache repinada no mesmo commit); sampling temp 1.0 / top-p 0.95 / top-k 20; workaround de scaling de ativações custa 10-30% (nota do PR); **decode ~42 tok/s curto / ~38 @1,7k, prefill ~1300 tok/s @8k** (fingerprint `b1-c7fc509`) (2026-10-22; ub4096 em 2026-10-26) |
| `Flint_40B_A2.5B_Uncensored` | stock | 131072 | Mesmo Flint, decensurado Heretic (electroglyph; abliterated 98→5 recusas/100) — GGUF Octopusman388 Q4_K_M (24,2 GB); MESMA receita da entry base (ncmoe 38 + `--load-mode none` + ub2048, temp 1.0/top-p 0.95/top-k 20); **known issue do autor: reasoning descontrolado em prompts sensíveis** — mitigado na entry com `--reasoning-budget 4096` + mensagem de fechamento (limita o drift, não elimina; presence-penalty não ajuda); TEXTO puro, SEM MTP/draft; **validado 2026-10-24: decode ~37 tok/s, VRAM pico 9874 MiB @128k** (~2,4 GB de folga); reasoning consome MUITOS tokens — orçar max_tokens generoso |
| `bonsai-27b` | PrismML | 131072 | PTQ1_0 + mmproj (visão validada); **KV q4_0 (desde 2026-10-20 — hoje é o default do zoo, ver regra 10; na época era override porque o macro usava q5_1, lento no fork PrismML — issue PrismML #191)**: com q4_0 **decode ~27 tok/s, prefill ~530 tok/s** (pós-unlock 2026-10-26); VRAM 10538 MiB |
| `bonsai-27b-heretic` | PrismML | — | **REMOVIDA em 2026-10-28** (GGUF apagado, ~6,2 GB): redundante com a `bonsai-27b-ada-uncensored` (LoRA AtomicChat na ada: refusals 99%→0% validado, decode ~43-50 t/s vs ~26, janela 262k). Medido antes da remoção: decode ~26 tok/s, prefill ~530 tok/s, VRAM 10544 MiB (2026-10-26) |
| `bonsai-27b-ada` | bonsai-ada | 262144 | MESMOS pesos PTQ1_0 do `bonsai-27b`, runtime alternativo (fork ada-ternary `2cadbfb6` = PrismML `adfffbe` + 71 patches do projeto bonsai-ada-surgery; engine `llama.cpp-bonsai-ada`). GGUF com head MTP ProCreations enxertada (trunk byte-idêntico, CaryPalmer HF); KV q4_0 TIERED (`--kv-vram-cells 131072` em VRAM, resto em RAM pinneada — bit-idêntico, janela 262k inteira); MTP self-draft (aceitação ~69-91%) + lookup n-gram; mmproj na GPU (+346 MiB — ViT na CPU com -t 5 levava ~60 s/img); harness-proofing (budget thinking 20480 c/ fechamento, effort "high" dos clients normalizado); **decode ~52 tok/s @5,5k, ~49 @45k, ~38 @130k, ~32 @175k** vs stock prism 23/16 nos mesmos prompts (2026-10-26); prefill igual ao stock (~500 curto, ~205-315 profundo); VRAM ~10,7 GB total (folga ~1,5 GB c/ display — linha KV conservadora de propósito, subir com dedicação exclusiva); SEM pdcache/sleep; cache de prompt em RAM cobre follow-up no slot (medido cache_n 129k). **Substitui o serving PrismML do 27B** (entry `bonsai-27b` mantida como fallback) |
| `bonsai-27b-ada-uncensored` | bonsai-ada | 262144 | MESMA receita da `bonsai-27b-ada` + LoRA rank-1 AtomicChat (9,7 MB, `--lora-scaled :1.5` — remove direção de recusa no grafo; sites verificados em CPU: os 129 alvos existem no GGUF 262k c/ MTP; refusals 99%→0% e MMLU 73.2→73.0 medidos pelo autor em prism-b10709); **validado 2026-10-28**: 3/3 probes sem recusa (lockpicking + phishing; sanidade harmless intacta — sem dano de sobre-recusa), **decode 43-50 tok/s em ctx curto** (paridade da base ada ~52), draft-mtp aceita com LoRA ativa; VRAM total 11194 MiB c/ display |
| `bonsai-9b` | PrismML | 196608 | Bonsai 2 9B (variante edge, denso); PTQ1_0 + mmproj Q8_0, mesma engine PrismML pinada; **KV bf16 @192k (2026-10-20 — q5_1 lento no fork, issue PrismML #191)**: **decode ~84 tok/s, prefill ~1530 tok/s** (pós-unlock 2026-10-26); VRAM 10870 MiB; visão validada; SEM MTP/DFlash (drafts no repo HF não baixados) |
| `bonsai-9b-uncensored` | PrismML | 196608 | Bonsai 2 9B + LoRA uncensored AtomicChat (rank-1, 3,2 MB, `--lora-scaled :1` — remove direção de recusa no grafo; base byte-idêntico; custo ~4,3 MMLU); MESMOS GGUFs/engine/KV bf16 @192k do `bonsai-9b`; **decode ~78 tok/s** (pós-unlock 2026-10-26); VRAM 10886 MiB; aplicação validada por logprobs distintos vs base; modelo thinking consome muitos tokens de raciocínio |

> **Removidos em 2026-10-28 — `Xing4.0_29B_A4B` + engine `llama.cpp-xing`**
> (GGUF ~17 GB apagado, imagem Docker removida): desclassificado pelo
> colapso de prefill em profundidade no fork (bateria 2026-10-27: 227 t/s
> @32k, 65 @130k vs ~1000 dos irmãos qwen3_5_moe — caminho de atenção do
> fork; investigação não vale o esforço). Entry, macro `docker-xing`,
> `engines/llama.cpp-xing/` e imagem removidos; reativável via git history
> se o fork (PR ggml-org#29012) corrigir o caminho de atenção.
>
> **Removidos em 2026-10-26 — política do floor de contexto**: modelo que
> não atende o mínimo de 128k é removido do zoo (não mais sufixo `_XXk`).
> Precedente: **K2-Horizon 36B MoVA** (`K2Horizon_36B_MoVA_40k`, GGUF 21 GB
> apagado) — KV de 192 KiB/tok (48 camadas full-attention, 8 KV heads × 128)
> + os 64 experts MoVA fixos na GPU (o `-ncmoe` não os cobre, piso ~6,5 GB)
> limitavam o ctx validado a **40k**. Medido antes da remoção: decode
> ~16-18 tok/s, prefill ~814 tok/s, VRAM 10665 MiB @40k — tecnicamente
> funcional, desclassificado pela política. Arch `k2_horizon` suportada
> desde PR ggml-org#29535; re-instalável se a política mudar.
>
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
> 86G apagados do disco (worst prefill do zoológico, ~8 tok/s); **engine e
> infra de build REMOVIDAS em 2026-10-28** (imagem `strata:latest` +
> `engines/strata/` — nunca foi reativada; re-instalável do zero via git
> history se um dia o Qwen3.8-Flash-Next justificar). **Variantes de
> contexto `_96k`/`_128k`
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

## Categorias de modelos (por MODELO, não por entry)

Um modelo pode pertencer a mais de uma categoria. Variantes do mesmo modelo
(GGUF/LoRA diferentes, ex.: base vs Heretic) herdam a categoria do modelo e
ganham a adicional quando aplicável.

- **SmallMoE** — MoE que PRECISA de offload de experts p/ RAM (`--load-mode
  none` + `-ncmoe`, regra 2); não cabem inteiras na VRAM:
  - LFM2.5-24B-A2B (64 experts top-4)
  - MiniCPM-V 4.7 35B-A3B (256 experts top-8, GDN)
  - Qwen3.6-35B-A3B (entries `Qwen3.6_35B_A3B` e Uncensored Hauhau;
    Code/It_* removidas em 2026-10-26 — variante MTP única cobre os casos)
  - Ornith-1.5-35B (APEX Compact)
  - Sage-A1.5 35B, Apodex-1.1 mini, Nex-N2.5 mini, BigBang v1
    (arch qwen3_5_moe, batch 2026-10-26)
  - Nemotron-3.5-Bolt-74B-A9B (quant "24GB" ~sub-Q4, mas com offload;
    MoE 74B/9B, mmproj + draft DFlash LiLiCorr — entry `Nemotron3.5_Bolt_74B`)
  - Flint-40B-A2.5B (256 experts top-6 + shared; base e Heretic)
  - Raon-1 mini 30B (KRAFTON): AVALIADO E BLOQUEADO 2026-10-26 — arch
    `raon1_mini` não existe no llama.cpp master nem em fork conhecido.
  - K2-Horizon 36B MoVA: REMOVIDO em 2026-10-26 — KV de 192 KiB/tok
    (48 camadas full-attention) + experts MoVA fixos na GPU limitavam o
    ctx a 40k, abaixo do floor de 128k (política de remoção, ver
    "Removidos").
- **Tiny** — densos que cabem 100% na VRAM em ~4-bit (Q4_K_M/QAT):
  - Gemma4-12B (QAT ~int4, multimodal visão+áudio)
  - MiniCPM-V 4.7 1B
  - Ornith-1.5-9B (MTP self-draft)
  - Qwen3.5-9B (HauhauCS)
  - MiMo-V2.6-Distill-Qwen-9B
- **SuperCompressed** — quantização ABAIXO de Q4_K_M e ainda assim 100% VRAM:
  - LFM2.5-24B-A2B na variante unsloth IQ2_M (7,5 GB, sem offload)
  - Bonsai 2 27B (PTQ1_0 ternário, engine PrismML) — base e Heretic
  - Bonsai 2 9B (PTQ1_0 ternário) — base e Uncensored (LoRA AtomicChat)
- **Uncensored** — sem censura (orthogonal às outras categorias):
  - Qwen3.6-35B-A3B Uncensored Hauhau Aggressive (também SmallMoE)
  - Qwen3.5-9B Uncensored HauhauCS (também Tiny)
  - LFM2.5-24B-A2B Uncensored LoRA AtomicChat (também SmallMoE)
  - MiniCPM-V 4.7 35B Uncensored LoRA AtomicChat (também SmallMoE)
  - Flint-40B-A2.5B Uncensored Heretic (também SmallMoE)
  - Bonsai 2 27B Uncensored LoRA AtomicChat sobre a entry ada (também
    SuperCompressed; rank-1 9,7 MB, scale 1,5)
  - Bonsai 2 9B Uncensored LoRA AtomicChat (também SuperCompressed)

Relevância para servir (uso agêntico/opencode): **alta** = Qwen3.6_35B_A3B,
bonsai-27b,
MiniCPM-V_4.7_35B, Gemma4_12B, LFM2.5_24B_A2B; **média** =
Ornith 35B; Flint_40B_A2.5B (agêntico de código).

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
