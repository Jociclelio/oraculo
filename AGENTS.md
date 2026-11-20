# oraculo — instruções para agentes

Servidor local de LLMs: **llama-swap** (proxy multi-engine em `127.0.0.1:8081`,
sobe um container Docker efêmero de llama.cpp por modelo sob demanda) +
**Open WebUI** (`:8080`) + Open Terminal (`:8000`), SearXNG (`:8888`), OpenWa
(`:2785`). Hardware alvo: **RTX 3060 12 GB** (GPU **compartilhada** com o
desktop pessoal) + 64 GB RAM (upgrade 2026-11-12, antes 32) + NVMe.

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

**Imagem stock (2026-11-17)**: `ghcr.io/ggml-org/llama.cpp:full-cuda`
build **12464**, commit **`d3c3e242c`** (1.0.0-dev; antes 12063/`2cbca389f`).
Engine pdcache repinada no MESMO commit (patch RE-PORTADO — o master mudou a
arquitetura de slot scheduling: `server_prompt`/`server_prompt_cache` migraram
para `server-slot-sched.{h,cpp}`, checkpoints viraram `shared_ptr<const>` e
`common_state_data` usa allocator no-init; hunks re-mapeados + lambdas
genéricas nos loops de checkpoint). PrismML repinado ao novo tip do branch
`prism` (`3f035ba66`, 2026-11-16). Bonsai-ada inalterado (`2cadbfb6` segue tip).
**ATENÇÃO builds locais**: a UI web "latest" do bucket ggml-org não passa mais
na validação do `ui-assets.cmake` (asset `workbox[hash].js` removido do bucket)
e quebra QUALQUER build de engine — fix nas duas engines locais:
`-DLLAMA_UI_HF_BUCKET=invalid/sem-ui` aciona o fallback oficial "building
without an embedded UI" (irrelevante: serving é por API). Fingerprint:
`b1-d3c3e24` (stock/pdcache), `b1-3f035ba` não existe — prism reporta
`0.7.0-dev (build 1, commit 3f035ba)`.
**Cache de experts MoE em VRAM (`--moe-cache-mib`, merged 2026-10-07 + SLRU
10-19) — VALE APENAS com cobertura alta de VRAM.** Rejeitado no regime antigo
(experts parcialmente na GPU, pouca folga): A/B 2026-11-03 no Qwen3.6 ncmoe 32
(ctx 8k): OFF 36,7 t/s → ON 1024 MiB 31,1 (-15%) → ON 256 MiB 19,4 (-47%) —
quanto menor o budget, pior (thrash); idem Hauhau 2026-10-26 (-21%).
**Porém com TODOS os experts na RAM + budget grande a conta inverte** (mesmo
A/B, ncmoe 99): + cache 6144 MiB → 48,3 t/s (+32%; 55-56 com MTP). Regra
prática: só usar quando os pesos GPU-residentes do modelo forem pequenos o
suficiente para o cache cobrir uma fração relevante dos experts (≥20-30%);
em serving @131k o budget tem de ser reduzido (4096 no Qwen3.6 — 6144 não
cabe). Pilotado na entry `Qwen3.6_35B_A3B` (ver tabela); outras entries
SmallMoE exigem validação individual de VRAM/RAM antes de replicar.
O PR alternativo por slots (`--moe-expert-cache`, ggml-org#27861) segue
DRAFT/não-mesclado — não usar.

**Regra do repo**: toda mudança deve ser refletida na documentação —
`docker-compose.yml` → `DOCKER.md`; `llama-swap/config.yaml` ou modelos →
`AGENTS.md`; `manage.sh`/fluxo de uso → `README.md`; requisitos → `README.md`.

---

## Comandos essenciais

```bash
./manage.sh start|stop|restart|status   # controle manual do stack (llama-swap + compose)
./manage.sh swap|services start|stop    # controle fino: só o proxy, ou só o compose
./manage.sh logs                        # log do proxy (docker logs -f llama-swap)
docker logs ls-<Modelo>                 # log do container do modelo carregado

# Testar modelo (o primeiro request dispara a carga; swap automático entre modelos)
curl -s http://localhost:8081/v1/models
curl -s http://localhost:8081/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"<Entry>","messages":[{"role":"user","content":"oi"}],"max_tokens":50}'
# timings no response: prompt_per_token_ms, predicted_per_token_ms, draft_n_accepted
```

Após editar `llama-swap/config.yaml`: `./manage.sh restart` (o config é
montado por bind — o container relê no start, sem rebuild de imagem). Não há
load/unload manual — apontar o request para outro `model` faz o swap
(`docker rm -f ls-<Anterior>`); descarrega sozinho após 5 min ocioso (`ttl: 300`).

**Boot**: llama-swap é container do compose desde 2026-11-16
(`restart: unless-stopped`) — sobe SOZINHO no boot junto com o
`docker.service` (enabled), como os serviços auxiliares. `./manage.sh start`
só é necessário após um `stop` manual (o que foi parado na mão não volta).
**Exceção (2026-10-30)**: as entries sem pdcache (PrismML/bonsai-ada) usam
`ttl: 0` — nunca saem por ociosidade; unload é só manual, por swap de outro
modelo ou pela liberação do gpu-shim antes da geração de imagem (regra 8).
O KV do slot fica residente até o `docker rm -f`.

---

## Arquitetura

- **`llama-swap/config.yaml` é a FONTE DA VERDADE** dos parâmetros de cada
  modelo (15 entries em 2026-11-12: 10 stock/pdcache + 2 PrismML + 3 bonsai-ada).
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
- **O llama-swap roda como CONTAINER do compose** (`docker-compose.yml` →
  serviço `llama-swap`, imagem `docker:cli` + binário Go estático montado de
  `bin/llama-swap`; antes era processo de HOST com `nohup`/pidfile, até
  2026-11-16). Precisa de `/var/run/docker.sock` (é ele quem dispara os
  containers de modelo) e `network_mode: host` (bind em `127.0.0.1:8081` +
  alcance pelos serviços, que também usam rede host). O repo é montado no
  **MESMO caminho absoluto** do host com `working_dir` apontando para ele —
  é isso que faz os mounts relativos do config (`-v ./models`,
  `-v ./data/llama-pdcache`) resolverem para caminhos do HOST; sem essa
  simetria os GGUFs não aparecem. `llama-swap/entrypoint.sh` limpa
  containers `ls-*` órfãos (rodando ou parados) antes de subir (os modelos
  são IRMÃOS, não filhos: sobrevivem a crash/SIGKILL do proxy e bloqueiam a
  carga seguinte por conflito de nome) e faz `exec` para o SIGTERM do
  `docker stop` chegar ao PID 1. Logs: `docker logs llama-swap` /
  `./manage.sh logs`.
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
   **EXCEÇÃO (2026-11-12): `Qwen3.8_Flash_Next_IQ3_S`** — usa `-lm mmap
   --lazy-mode on` sem `--load-mode none` porque o shard 2 (tabela n-gram
   PLE, 28,8 GB) exige mmap lazy; load none copiaria ~81 GB p/ RAM → OOM.
   Decode validado em ~20 t/s (sem colapso): o page cache dos 64 GB de RAM
   segura o shard 1 inteiro residente; se o decode desabar após pressão de
   memória, qualquer leitura re-aquece o cache (ou considerar
   `-lm mmap+mlock`).
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
    **Mapa da VRAM (medido 2026-11-09, GPU idle, 12288 MiB totais)**:
    LLM 10460 · desktop (Hyprland 77 + firefox 134-270 + vesktop 89 + 8
    kitty ~200 + ashell 33 + Xwayland/polkit 7) ~540 · reserva do driver
    ~320 (não atribuída a processo) · ComfyUI **104-220** de contexto CUDA
    — `POST /free` com `free_memory:true` devolve pesos ao allocator mas
    **não derruba esse piso** (A/B: 1070→1070 MiB); só `docker stop comfyui`
    zera (~-105 MiB medidos). `./manage.sh vram` imprime o mapa
    (total/usado/livre + todos os processos via `nvidia-smi pmon`, inclui
    gráficos, que `--query-compute-apps` omite) e
    `./manage.sh unload --hard` = unload do LLM + para o ComfyUI (religar
    com `docker start comfyui` ou `./manage.sh services start`).
    **12 GiB inteiros NÃO são alcançáveis com o driver carregado**: os
    ~540 MiB do desktop só saem parando a sessão gráfica
    (`systemctl isolate multi-user.target`, exige TTY/SSH) e os ~320 MiB
    do driver só com `rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia`
    (headless). Teto prático: **~10,8 GiB livres** com desktop ativo
    (10 900-11 100 MiB medidos, ComfyUI parado; 10 872 com ComfyUI idle) e
    **~11,6 GiB** headless.
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
    o KV. **Nuance 2026-11-12**: no Qwen3.6 Hauhau (KV mínimo — só 10/41 camadas
    têm KV, ~10,6 KiB/tok), q5_1/q5_1 = q4_0/q4_0 medidos e2e (decode curto
    49,9 vs 49,3 t/s; prefill @3,5k 1527 vs 1526 t/s) — o castigo do q5_1
    aparece em modelos de KV/token alto (MiniCPM/MiMo/Gemma4) e em ctx
    profundo; no A/B o log ainda mostra `no FlashAttention vector kernel
    ... q5_1-q5_1, converting to f16 (slow)`, mas o impacto é ruído nesse
    footprint. EXCEÇÕES bonsai no fork PrismML: bf16 nos 9B (medido — teto de
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
| `LFM2.5_24B_A2B` | stock | 131072 | LiquidAI raciocínio puro agêntico, MoE 24B/2,45B (64 experts top-4); **rework 2026-11-03 (build 12063) — cache de experts quentes**: `ncmoe 20→99` (TODOS os experts na RAM, ~1,95 GB de pesos na GPU) + `--moe-cache-mib 7168` (máximo no envelope @131k) — **decode ~52,7 t/s curto / ~32,9 @129k (baseline 47,4 / 29,4 = +11-13%), prefill @129k ~1449 t/s (baseline ~1732, -16% — custo do streaming de todos os experts)**; VRAM pico 10292 MiB (baseline 9941); A/B @8k da curva de cobertura: sem cache 27,5 → 6 GiB 44,7 → 8 GiB 62,1 t/s (joelho ~70-75% de cobertura); ub2048; sampling temp 0.1 / top-k 50 / rep 1.05; sem MTP (draft DSpark não publicado); custo de RAM: ~13,5 GB fixados (+~5 GB) |
| `LFM2.5_24B_A2B_IQ2_M` | stock | 131072 | unsloth UD IQ2_M (7,5 GB) — a mesma LFM2.5 em **100% GPU** (sem `--load-mode none`/`-ncmoe`); **decode ~106 tok/s, prefill ~2960 tok/s** (pós-unlock 2026-10-26 — o mais rápido do zoo); 128k validado de ponta a ponta (VRAM 9940 MiB @130k pré-unlock); sem MTP; sampling temp 0.1 / top-k 50 / rep 1.05 |
| `LFM2.5_24B_A2B_Uncensored` | stock | 131072 | MESMA receita da `LFM2.5_24B_A2B` (incl. rework 2026-11-03: ncmoe 99 + `--moe-cache-mib 7168` — ver entry base) + LoRA rank-1 AtomicChat (24 MB, `--lora-scaled :1.75` — blocos 14-39: mixers + ffn_down dos 64 experts; sites verificados em CPU: 52/52 no Q4_K_M; autor: refusals 96,3%→1,2%, MMLU 64,4→65,6); **validado 2026-11-03 no serving**: carga OK c/ cache de experts + LoRA, decode ~46,4 t/s curto, VRAM 10103 MiB (c/ display) |
| `Qwen3.6_35B_A3B_Hauhau_Aggressive` | stock | 131072 | Uncensored Aggressive, multimodal; ncmoe 29; ub2048 + `--load-mode none`; **re-medido 2026-11-12 pós-troca de CPU + RAM 64 GB**: decode curto **~49,3 t/s** (+20% vs 41 de 2026-10-26), decode @47k ~36 t/s, prefill @3,5k **~1526 t/s** (+39% vs ~1100), prefill @48k ~1422 t/s; re-confirmado 2026-11-18 no build 12464: decode 47,0 t/s / prefill 1468 t/s @3,7k. VRAM 10714 MiB; **A/B KV q5_1 vs q4_0: PARIDADE** (decode 49,9 vs 49,3; prefill @3,5k 1527 vs 1526 — todo o ganho é hardware, ver nuance na regra 10); SEM MTP (GGUF sem tensors nextn — spec inaplicável; `--moe-cache-mib` testado e rejeitado: decode -21%). **TESTADO NO STRATA 2026-11-18 (`--family qwen36`, UD-Q4_K_XL unsloth, ctx 32k — 128k OOM na 12 GB): decode 37,4-39,2 t/s / prefill ~1170 t/s — o llama.cpp VENCE no Qwen3.6 (o 59,7 t/s do report deles não se reproduz a 3,7k de profundidade; path qwen36 é engine separada, menos madura). O Hauhau uncensored só existe em llama.cpp; NÃO migrar**. Entry BASE `Qwen3.6_35B_A3B` removida em 2026-11-12 (ver removidos) |
| `Ornith1.5_9B` | stock | 131072 | Ornith-1.5-9B Q4_K_M + mmproj BF16 (ornith-ai); variante edge DENSA da família (arch qwen35), raciocínio agêntico `<think/tool_call>`; head MTP embutida (nextn=1) → draft-mtp self-draft n=2 (aceitação ~50% pós-unlock); **decode ~58 tok/s, prefill ~1600 tok/s** (2026-10-26); VRAM 10244 MiB |
| `MiMo2.6_9B` | stock | 131072 | MiMo-V2.6-Distill-Qwen-9B (XiaomiMiMo, distill em base Qwen3.5; arch qwen35, denso) Q4_K_M bartowski + mmproj f16; reasoning separado; **SEM MTP** (header sem nextn); **decode ~53 tok/s, prefill ~1615 tok/s** (pós-unlock 2026-10-26); VRAM 9508 MiB; visão validada; sampling temp 0.6 / top-p 0.95 / top-k 20 (generation_config oficial) |
| `bonsai-27b-heretic` | PrismML | — | **REMOVIDA em 2026-10-28** (GGUF apagado, ~6,2 GB): redundante com a `bonsai-27b-ada-uncensored` (LoRA AtomicChat na ada: refusals 99%→0% validado, decode ~43-50 t/s vs ~26, janela 262k). Medido antes da remoção: decode ~26 tok/s, prefill ~530 tok/s, VRAM 10544 MiB (2026-10-26) |
| `bonsai-27b-ada` | bonsai-ada | 262144 | MESMOS pesos PTQ1_0 do `bonsai-27b`, runtime alternativo (fork ada-ternary `2cadbfb6` = PrismML `adfffbe` + 71 patches do projeto bonsai-ada-surgery; engine `llama.cpp-bonsai-ada`). GGUF com head MTP ProCreations enxertada (trunk byte-idêntico, CaryPalmer HF); KV q4_0 TIERED (`--kv-vram-cells 131072` em VRAM, resto em RAM pinneada — bit-idêntico, janela 262k inteira); MTP self-draft (aceitação ~69-91%) + lookup n-gram; mmproj na GPU (+346 MiB — ViT na CPU com -t 5 levava ~60 s/img); harness-proofing (budget thinking 20480 c/ fechamento, effort "high" dos clients normalizado); **decode ~52 tok/s @5,5k, ~49 @45k, ~38 @130k, ~32 @175k** vs stock prism 23/16 nos mesmos prompts (2026-10-26); prefill igual ao stock (~500 curto, ~205-315 profundo); VRAM ~10,7 GB total (folga ~1,5 GB c/ display — linha KV conservadora de propósito, subir com dedicação exclusiva); SEM pdcache/sleep; cache de prompt em RAM cobre follow-up no slot (medido cache_n 129k). **Substitui o serving PrismML do 27B** (entry `bonsai-27b` removida 2026-10-30 — ver removidos) |
| `bonsai-27b-ada-uncensored` | bonsai-ada | 262144 | MESMA receita da `bonsai-27b-ada` + LoRA rank-1 AtomicChat (9,7 MB, `--lora-scaled :1.5` — remove direção de recusa no grafo; sites verificados em CPU: os 129 alvos existem no GGUF 262k c/ MTP; refusals 99%→0% e MMLU 73.2→73.0 medidos pelo autor em prism-b10709); **validado 2026-10-28**: 3/3 probes sem recusa (lockpicking + phishing; sanidade harmless intacta — sem dano de sobre-recusa), **decode 43-50 tok/s em ctx curto** (paridade da base ada ~52), draft-mtp aceita com LoRA ativa; VRAM total 11194 MiB c/ display |
| `bonsai-27b-ada-8g-2u` | bonsai-ada | 262144 | variante headless p/ PC externo de 8 GB, **2 usuários + visão** (2026-11-03): MESMOS GGUFs da ada + `-np 2 --kv-unified` (o KV tiered do fork SÓ ativa com `n_stream==1`, verificado no commit 2cadbfb — com `-np 2` não-unificado ele desativa SILTENCIOSAMENTE e o KV inteiro tem de caber em VRAM); **SEM draft-mtp**: o rollback do draft exige RS buffer (estados GDN) = 48 camadas × 3,127 MiB × 2 seqs × (1+n_rs_seq) POR CONTEXTO, e o draft cria um 2º contexto — ~1,66 GB @n_rs_seq 4 (n_rs_seq = `draft.n_max` = max(n-max, n-max-tail)); spec = `ngram-mod` puro (mantém boost em rewrites/edits; decode ~26 t/s single, ~13 t/s por usuário com os 2 ativos); KV tiered linha 24576 → ~12k tok/usuário residentes, rabo até 131k/usuário em RAM pinneada via PCIe (conforto ~20-30k/usuário); mmproj na GPU c/ `--image-max-tokens 1024` (spike real do ViT só +126 MiB numa 1500×1500 — a estimativa worst-case de 873 MiB do loader é conservadora); **VRAM 7716 MiB medido** (imagem alta processada; folga ~476 MiB em 8192); 2 slots validadas em paralelo c/ visão. PC alvo: Turing+ (VMM; Pascal desativa o tier), RAM ≥ 16 GB, display fora da placa |
| `LFM2.5_24B_A2B_2G` | stock | 131072 | variante headless p/ PC externo de ~2 GB (2026-11-03): MESMO Q4_K_M da `LFM2.5_24B_A2B` com `-ncmoe 40` (TODOS os experts ~13,3 GB fixados na RAM; GPU fica só c/ ~615 MiB de pesos: attn 57,5 + conv/GDN 270,7 + embd/output 205 + dense-FFN blocos 0-1 ~81) + `-b 1024 -ub 256` (compute buffers mínimos) + KV q4_0 do macro (10 camadas GQA × 512+512 = 5,6 KiB/tok → 720 MiB @131k); **VRAM 1822 MiB medido** (folga 226 MiB @2048); janela 131k INTEIRA (`-np 1`; 2 usuários = `-np 2`, 65k/slot); **decode ~29,5 t/s / prefill ~57 t/s** medidos no i5-9400F (CPU-bound mas viável — o A2B 2,45B ativo é leve); sem MTP/visão. PC alvo: RAM ≥ 16 GB |
| `bonsai-9b` | PrismML | 196608 | Bonsai 2 9B (variante edge, denso); PTQ1_0 + mmproj Q8_0, mesma engine PrismML pinada; **KV bf16 @192k (2026-10-20 — q5_1 lento no fork, issue PrismML #191)**: **decode ~84 tok/s, prefill ~1530 tok/s** (pós-unlock 2026-10-26); VRAM 10870 MiB; visão validada; SEM MTP/DFlash (drafts no repo HF não baixados) |
| `bonsai-9b-uncensored` | PrismML | 196608 | Bonsai 2 9B + LoRA uncensored AtomicChat (rank-1, 3,2 MB, `--lora-scaled :1` — remove direção de recusa no grafo; base byte-idêntico; custo ~4,3 MMLU); MESMOS GGUFs/engine/KV bf16 @192k do `bonsai-9b`; **decode ~78 tok/s** (pós-unlock 2026-10-26); VRAM 10886 MiB; aplicação validada por logprobs distintos vs base; modelo thinking consome muitos tokens de raciocínio |
| `Qwen3.8_Flash_Next_IQ3_S` | stock (pdcache) | 131072 | Qwen3.8-Flash-Next GSQ-RCO IQ3_S (ISTA-DASLab) — o "Strata" de volta em GGUF padrão (arch `qwen4exp` na stock 12063; a engine dedicada Niko1221/Strata continua removida); MoE híbrido 177B: 48 camadas (12 full-attn GQA 24q/2kv a cada 4 + conv/SSM), 512 experts top-10, ctx nativo 262k; GGUF 83,6 GB em 2 shards — shard 2 (28,8 GB, tabela n-gram PLE IQ4_NL) fica mmap em disco via `-lm mmap --lazy-mode on`, **NÃO usa `--load-mode none`** (copiaria ~81 GB p/ RAM → OOM; exceção documentada à regra 2 — shard 1 fica no page cache ~52 GB, viável nos 64 GB de RAM desde 2026-11-12); `-ncmoe 46` (2 camadas de experts na GPU) + ub2048 + `-t 16` (experts rodam na CPU, 32 threads do host); **decode ~18,6-20,5 t/s, prefill ~425-450 t/s @4,4k** (A/B: ncmoe 44+ub512 = 270 t/s, -t 5 = 17,5 t/s); VRAM ~9,8-10,3 GiB (folga ~2); thinking pesado — `enable_thinking:false` via chat_template_kwargs p/ chat casual; SEM mmproj na receita (0,91 GB não cabe — mmproj já baixado no dir; visão a validar). ATENÇÃO page cache: coexistir com outro modelo grande no cache evicta o shard 1 e derruba decode p/ ~13 t/s — resolver com `posix_fadvise(DONTNEED)` no GGUF do outro modelo |
| `Qwen3.8_Flash_Next_IQ2_0` | stock (pdcache) | 131072 | MESMA arch/receita da IQ3_S na quant **Q2_0** (66,4 GB: shard 1 37,6 GB + shard 2 hardlinkado da IQ3_S — byte-idênto, ver MODELS_INSTALL.md); evita os formatos de lookup table — **decode ~26 t/s e prefill ~573-577 t/s @4,4k (+30% vs IQ3_S nos dois)**, decode estável entre runs (25,9-26,5); `-lm mmap+mlock` (shard 1 PINADO na RAM, estilo Strata all-resident — throughput igual ao mmap puro, o valor é imunidade a eviction; exigiu `--ulimit memlock=-1` no macro; RAM disponível 54→22 GiB); `-ncmoe 44` (A/B: ncmoe 42 = mesmos 26 t/s mas só 578 MiB de VRAM livre); `-t 16` (físicos do 5900XT: 16→26 t/s, 24→25,1, 32→20,1 — SMT atrapalha); `--moe-cache-mib 1536` rejeitado (-14%); VRAM ~10,0 GiB (folga 2,0); qualidade: task avg 89,07 vs 93,26 da IQ3_S (card ISTA) — o trade 4 pontos por +30% de velocidade; PARIDADE com a engine Strata sem drafter na mesma máquina (bench comunidade 2026-10-09: Q2_0 com MTP+lookup 42-45 t/s, IQ2_XS sem MTP 35,9, IQ3_S sem MTP 17,0 — nossa IQ3_S 18,6-20,5 já supera; o gap restante deles é o drafter MTP+lookup, sem GGUF p/ llama.cpp) |
| `Qwen3.8_Flash_Next_Abl_Q2_0` | stock (pdcache) | 131072 | **Abliterated (SC117) em llama.cpp — FALLBACK da entry Strata** (mesma receita da `Qwen3.8_Flash_Next_IQ2_0`: mmap+mlock, ncmoe 44, t 16; sha256 verificado vs LFS). Medido 2026-11-17 (build 12464, prompt real 3,7k): decode ~23,6 t/s, prefill ~425 t/s. Experimentos 2026-11-17 (NÃO aplicados): `--moe-cache-mib 1024 --moe-cache-cpu-share 0.5` = +27% em prompt SINTÉTICO mas NEUTRO/NEGATIVO em texto real (calibrar SEMPRE com texto real; `benchmarks/calibrate_moe.sh`); draft MTP: aceitação 77,5% mas 4,14 GB não cabem na VRAM e com draft na CPU o ganho evapora — SEM MTP no llama.cpp; tuner oficial `scripts/moe-cache-tune.py` não roda na 3060 12 GB (menor cache calibrável 3,2 GiB > sala livre). VRAM ~10,4 GiB |
| `Strata_Abl_Q2_0` | **Strata** (docker) | 131072 | **VENCEDOR GERAL do zoo** — Qwen3.8-Flash-Next abliterated na engine dedicada Niko1221 (container oficial `ghcr.io/niko1221/strata:latest-cuda13`, engine 0.1.59/DFlash2). Medido 2026-11-18 (prompt real 3,7k): **decode ~55-58 t/s, prefill ~930-1000 t/s — ~2,4× o llama.cpp** (23,6/425); nativo 0.1.60/MTP fez 62-71 t/s. Container gerenciado pelo llama-swap com entrypoint custom (`llama-swap/strata-entrypoint.sh` — o launch --no-tui daemoniza e retorna; wrapper mantém vivo, monitora status, stop gracioso no SIGTERM) + macro `docker-stop-strata` (stop -t 110). `--no-api-key --access local` (llama-swap não injeta Authorization). Monta Strata-data nativo (modelo/MTP) + GGUFs do oraculo mesmo caminho absoluto. Abliterated Q2_0 roda SEM pack (streama do GGUF — pack do ISTA não vale: ArenaExpertSource). DFlash2 = 1 request por vez. VRAM ~11,4 GiB. **CPU pool = 15 workers (1 por núcleo físico, 16 do 5900XT, um reservado p/ o host-callback da GPU) — DELIBERADO e ÓTIMO: A/B 2026-11-18 com `--pool-cores 0-31` (32 lógicos/SMT) DERRUBOU o decode p/ 33-39 t/s (-40%); mesmo padrão do A/B -t do llama.cpp (16>24>32). Não mexer.** **VISÃO VALIDADA 2026-11-18** (única entry do Flash-Next com visão — o mmproj 0,91 GB não cabe nas entries llama.cpp): picture reader na CPU (16 threads, custo ZERO de VRAM), imagem ≈256 tokens de prompt, teste de formas/cores/posições em pt-BR 100% correto. **SIMULAÇÃO 5800X 2026-11-18** (`--pool-cores 0-7`, 8 físicos de 1 CCD): decode 34,7-35,7 t/s e prefill ~923 t/s vs controle default 52,8-53,8 na mesma sessão — **o 5900XT (16 físicos) vale ~+50% de decode sobre um 8-core neste workload** (quase linear com os workers: o pool da CPU é o gargalo no single-GPU; um 5800X rodaria ~35 t/s). **DDR4-3400 CL16 (OC 2026-11-20, antes 3200)**: pool default fez 53,3-57,0 (mediana ~54) vs 52,8-53,8 @3200 = **+2-3%, perto do ruído** (a teoria pedia +6,25% de banda; só a fração streaming do decode escala com banda). **`--pool-cores 0-15` (16 workers, incluindo o core do host-callback) REJEITADO: 35,0-39,4 t/s (-30%)** — o 16º worker disputa o core que alimenta a GPU; o default de 15 workers da engine está certo. Se um container morrer sem stop gracioso, o state stale trava o próximo launch ("A model is already running") — limpar com `strata launch --stop --data-dir /data/Strata-data` num container efêmero COM os mounts de state |
| `Strata_Abl_IQ3_S` | **Strata** (docker) | 131072 | IQ3_S abliterated no Strata. **Validado 2026-11-18** (prompt real 3,7k): **decode ~30,9 t/s (+72% vs llama.cpp ~18), prefill ~807 t/s** (vs disk-bound 7,5-10,5 frio / ~450 quente) — MELHOR IQ3_S do zoo; swap+load total 72,7 s. **Re-medido 2026-11-20 com DDR4-3400: decode settle ~35-36 t/s (+15% vs 30,9 @3200 — a quant mais faminta de banda, ~1 GB/token lido da RAM, escala mais com o OC que a Q2_0 (+2-3%)); prefill ~546-933 t/s (cache aquecendo)**. Pack auto-gerado em `packs/iq3_s` (~1,5 GB — modo streaming, não o experts.bin residente de 50 GB do report da comunidade; resident pool é otimização futura). ATENÇÃO: os headers do GGUF abliterated fazem o setup avisar "look like swift IQ3_S" — ignora e funciona. VRAM ~11,4 GiB |
| `Qwen3.8_Flash_Next_Abl_IQ3_S` | stock (pdcache) | 131072 | **Abliterated (SC117)** — irmã da IQ3_S ISTA com transplante byte-a-byte de 144 tensors (`ssm_out`/`attn_output`/`ffn_down_shexp`/`ffn_down_exps`); MESMA receita e MESMOS custos (tipo por tensor idêntico ao upstream; shard 2 hardlinkado). Medido 2026-11-17 (build 12464): decode ~18 t/s estável; prefill DOMINADO POR DISK no 1º request após idle (7,5-10,5 t/s — o shard 1 de 52 GB NÃO cabe no page cache de 62 GB; a referência ~450 t/s exige cache quente dedicado) — NESTE setup perde para a Q2_0 em tudo. **2026-11-20: cpuset 0-15 nos macros** (o scheduler amontoava os 16 threads no CCD1 COM SMT ativo — CCD1 80%+SMT 80%, CCD0 ocioso; com cpuset: CCD0/CCD1 ~58% cada, SMT de folga) — decode **paridade** (17,5-17,9 vs 18,6-20,5 dentro do ruído; o desktop ativo agora divide os cores pinados) |

> **Removidos em 2026-11-12 — consolidação em torno do Qwen3.8-Flash-Next
> (4 modelos, ~98 GB de GGUFs apagados):** `Qwen3.6_35B_A3B` (MTP; 21,9 GB —
> a variante uncensored segue na entry Hauhau_Aggressive),
> `Ornith1.5_35B_MTP` (17,0 GB), `MiniCPM-V_4.7_35B` + `_Uncensored` (20,8 GB
> c/ mmproj + LoRA) e `Flint_40B_A2.5B` (21,8 GB). Todos re-instaláveis via
> `MODELS_INSTALL.md`.

> **Removidos em 2026-10-30 — poda do zoo a pedido do owner (10 entries,
> ~156 GB de GGUFs apagados):**
> `SageA1.5_35B`, `Apodex1.1_35B`, `NexN2.5_35B`, `BigBangv1_35B` (o batch
> qwen3_5_moe inteiro — redundantes com Qwen3.6/MiMo/Ornith; ~91 GB),
> `Nemotron3.5_Bolt_74B` (decode mínimo do zoo ~19 t/s; pesos + mmproj +
> draft DFlash LiLiCorr ~24,8 GB),
> `Flint_40B_A2.5B_Uncensored` (Heretic; entry base Flint removida em
> 2026-11-12; ~24,2 GB),
> `Qwen3.5_9B_HauhauCS` (~6,5 GB), `LFM3_1.7B` (inclui a alternativa
> QAD-Q4_0; ~2,1 GB), `MiniCPM-V_4.7_1B` (~1,8 GB) e `bonsai-27b`
> (trunk PTQ1_0 ~5,9 GB; o mmproj Q8_0 permanece — compartilhado com as
> entries ada; serving do 27B já migrado para a engine
> llama.cpp-bonsai-ada). Todos re-instaláveis via `MODELS_INSTALL.md`.
> A engine PrismML segue em uso pelos bonsai-9b.

> **Removidos em 2026-10-28 — `Xing4.0_29B_A4B` + engine `llama.cpp-xing`**
> (GGUF ~17 GB apagado, imagem Docker removida): desclassificado pelo
> colapso de prefill em profundidade no fork (bateria 2026-10-27: 227 t/s
> @32k, 65 @130k vs ~1000 dos irmãos qwen3_5_moe — caminho de atenção do
> fork; investigação não vale o esforço). Entry, macro `docker-xing`,
> `engines/llama.cpp-xing/` e imagem removidos; reativável via git history
> se o fork (PR ggml-org#29012) corrigir o caminho de atenção.
> **Strata REATIVADO EM OUTRA FORMA em 2026-11-12**: o Qwen3.8-Flash-Next
> voltou ao zoo como `Qwen3.8_Flash_Next_IQ3_S` em GGUF padrão llama.cpp
> (arch `qwen4exp` no master; ISTA-DASLab GSQ-RCO) — a engine dedicada
> Niko1221/Strata e `engines/strata/` continuam removidos.
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
  - Qwen3.6-35B-A3B (entry base MTP REMOVIDA em 2026-11-12; resta a
    Uncensored Hauhau)
  - Qwen3.8-Flash-Next (512 experts top-10; entries `Qwen3.8_Flash_Next_IQ3_S`
    e `_IQ2_0`, 2026-11-12 — caso LIMITE da categoria: 36-52 GB de experts no
    page cache via mmap, exigiu o upgrade de RAM p/ 64 GB; exceção à regra 2)
  - Sage-A1.5 35B, Apodex-1.1 mini, Nex-N2.5 mini, BigBang v1
    (arch qwen3_5_moe, batch 2026-10-26): REMOVIDOS em 2026-10-30 — ver
    "Removidos".
  - Nemotron-3.5-Bolt-74B-A9B (quant "24GB" ~sub-Q4, mas com offload;
    MoE 74B/9B, mmproj + draft DFlash LiLiCorr): REMOVIDO em 2026-10-30 —
    ver "Removidos".
  - Raon-1 mini 30B (KRAFTON): AVALIADO E BLOQUEADO 2026-10-26 — arch
    `raon1_mini` não existe no llama.cpp master nem em fork conhecido.
  - K2-Horizon 36B MoVA: REMOVIDO em 2026-10-26 — KV de 192 KiB/tok
    (48 camadas full-attention) + experts MoVA fixos na GPU limitavam o
    ctx a 40k, abaixo do floor de 128k (política de remoção, ver
    "Removidos").
- **Tiny** — densos que cabem 100% na VRAM em ~4-bit (Q4_K_M/QAT):
  - Gemma4-12B (QAT ~int4, multimodal visão+áudio)
  - Ornith-1.5-9B (MTP self-draft)
  - MiMo-V2.6-Distill-Qwen-9B
  - MiniCPM-V 4.7 1B, Qwen3.5-9B (HauhauCS) e LFM3-1.7B: REMOVIDOS em
    2026-10-30 — ver "Removidos".
- **SuperCompressed** — quantização ABAIXO de Q4_K_M e ainda assim 100% VRAM:
  - LFM2.5-24B-A2B na variante unsloth IQ2_M (7,5 GB, sem offload)
  - Bonsai 2 27B (PTQ1_0 ternário, engine bonsai-ada) — base e Uncensored
    (entry PrismML `bonsai-27b` removida 2026-10-30)
  - Bonsai 2 9B (PTQ1_0 ternário) — base e Uncensored (LoRA AtomicChat)
- **Uncensored** — sem censura (orthogonal às outras categorias):
  - Qwen3.6-35B-A3B Uncensored Hauhau Aggressive (também SmallMoE)
  - LFM2.5-24B-A2B Uncensored LoRA AtomicChat (também SmallMoE)
  - Bonsai 2 27B Uncensored LoRA AtomicChat sobre a entry ada (também
    SuperCompressed; rank-1 9,7 MB, scale 1,5)
  - Bonsai 2 9B Uncensored LoRA AtomicChat (também SuperCompressed)
  - Qwen3.5-9B HauhauCS e Flint-40B Heretic: REMOVIDOS em 2026-10-30 —
    ver "Removidos".

Relevância para servir (uso agêntico/opencode): **alta** = Qwen3.6_35B_A3B,
bonsai-27b-ada,
Gemma4_12B, LFM2.5_24B_A2B; **média** =
Ornith1.5_9B / MiMo2.6_9B (edge).

---

## docker-compose (llama-swap + serviços auxiliares)

`llama-swap` (container do proxy — ver "Arquitetura"; `network_mode: host`,
Docker socket, repo montado no mesmo caminho; `restart: unless-stopped`, então
sobe no boot) · `open-webui` (host `:8080`, conecta ao proxy via `OAI_API_BASE`,
`WEBUI_SECRET_KEY` obrigatório p/ persistir tokens OAuth/MCP) ·
`open-terminal` (execução agêntica `:8000`, requer modelo com Function
Calling = Native) · `searxng` (`:8888`, JSON habilitado) · `openwa` +
`openwa-docker-proxy` (WhatsApp/MCP `:2785/mcp`, key em
`data/openwa/.api-key`; proxy restrito `tecnativa/docker-socket-proxy` — com
o llama-swap, são os DOIS containers que falam com o Docker socket, por
motivos distintos: escopo restrito do openwa x orquestração de containers
de modelo) · `mcp-playwright` (`:8931/mcp`, `mcr.microsoft.com/playwright/mcp`
pinado, headless) · `mcp-memory` (`:8932/mcp`, supergateway faz a ponte
stdio→Streamable HTTP do `@modelcontextprotocol/server-memory`; grafo em
`mcp-data/memory.json`, **compartilhado com o memory do opencode** —
`MEMORY_FILE_PATH` aponta para esse caminho) · `comfyui` (`:8188`,
yanwk/comfyui-boot pinado; Qwen-Image 2.1 Turbo int8, geração + edição) ·
`mcp-comfyui` (`:8933/mcp`, build local em `mcp/comfyui-mcp-server` — joenorton
pinado + patch oraculo; tools `generate_image`/`edit_image` com schema tipado
derivado dos placeholders `PARAM_*` em `comfyui/mcp-workflows/`;
**substituiu a integração nativa ComfyUI do Open WebUI em 2026-11-09** —
`image_generation.enable`/`images.edit.enable` desligados no `webui.db`,
receita preservada p/ rollback; hit no gpu-shim `:8188`, regra 8 intacta).
Detalhes: `DOCKER.md`.

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
  `docker logs --tail 50 llama-swap` → `docker logs ls-<Modelo>` (enquanto Up).
- **Falha de carga / `exit 125`**: primeiro `nvidia-smi` (jogo/desktop
  ocupando VRAM → OOM de compute buffer); senão, retry ou restart (flake
  conhecido). Container de modelo órfão (`ls-*`) é limpo pelo
  `llama-swap/entrypoint.sh` no start do proxy; manual: `docker rm -f ls-<Modelo>`.
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
  **UPGRADE 2026-11-12: v263 → v272** (`llama-swap/install.sh` baixa o
  latest). Motivo: o capcompat do v263 quebrava com os Qwen3.8-Flash-Next —
  o /props do llama.cpp reporta `chat_template_caps.reasoning_effort_levels`
  como ARRAY e o v263 esperava bool; a falha de discovery desregistrava o
  modelo do router e TODA request posterior dava 404 "no router for
  requested model" (as 1-2 primeiras passavam pelo fast-path antes do
  probe). O v272 ainda loga a falha no 1º probe mas re-probeia com sucesso
  e o router se mantém — sleep/wake e swaps validados.
- **YAML inválido**: o container `llama-swap` entra em crash-loop no start —
  o erro aparece em `docker logs --tail 30 llama-swap` (ex.: chave duplicada
  no entry). Corrigido o config, `./manage.sh swap restart`.
- **Storage**: `du -sh models/*/` — repo agora no **NVMe** (`/home/jocic/oraculo`,
  migrado do SATA 220 GB em 2026-10-14); GGUFs órfãos (sem entry no
  config) são candidatos a remoção.
