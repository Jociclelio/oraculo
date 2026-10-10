# Plano: llama-swap multi-engine (stock + Bonsai/PrismML + Strata)

Estado: concluído (todas as tasks fechadas ou resolvidas por subtasks; critérios de conclusão com evidência nas tasks: models list 002/004, swap 002/004, Bonsai responde 004, manage.sh 001, compose válido 006, docs sincronizadas 008, bateria final 007 resolvida por 007-1/007-2)

## Objetivo

Substituir o serving single-server (container `llama-cpp` + `models.ini`) por
**llama-swap** como proxy único em `127.0.0.1:8081`, com três engines por baixo:

1. **llama.cpp stock** (imagem oficial `ghcr.io/ggml-org/llama.cpp:full-cuda`) —
   todos os modelos atuais do `models.ini`, um container efêmero por modelo.
2. **Bonsai 2 (fork PrismML)** — imagem Docker dedicada construída no repo
   (`engines/llama.cpp-prismml/`), servindo os GGUFs movidos de
   `/home/jocic/bonsai-llm` para `models/`. Entry primária: **PTQ1_0** (<6 GB, com
   mmproj). PQ2_0 mantida como entry secundária. Sem MTP (não baixado).
3. **Strata (Qwen3.8-Flash-Next)** — infra preparada (Dockerfile adaptado do
   upstream + entry desabilitada/comentada no config), sem baixar o modelo (~70 GB).

Posicionamento explícito no repo: **stack para 1 usuário por vez**; entradas
paralelas (`np>1`) só como exceção pontual para modelos pequenos; meta de
prefill/decode razoável com contexto ≥ 64k (128k quando VRAM e prefill permitirem).

## Abordagem

1. **llama-swap (host)**: instalar binário de release (script `llama-swap/install.sh`
   baixa para `bin/`). `manage.sh` reescrito: `start` sobe o llama-swap em background
   (pidfile + log em `logs/`), `stop` encerra. Porta `8081` — WebUI não muda
   (`OAI_API_BASE=http://localhost:8081/v1` já está no `webui.db`).
2. **`llama-swap/config.yaml`**:
   - macro para `cmd` Docker stock (`--gpus all`, mount `./models:/models`, `-fa on`,
     `--jinja`, `ttl` ≈ 300 s substituindo `sleep-idle-seconds`);
   - uma entry por modelo atual do `models.ini` (tradução INI → flags);
   - entries `bonsai-27b` (PTQ1_0, mmproj, ctx 65536 a validar — fallback
     documentado p/ 49152) e `bonsai-27b-pq2_0` usando a imagem local do fork;
   - entry Strata desabilitada (comentada) com `MODEL=coder`, `FAMILY=coder`.
3. **`engines/llama.cpp-prismml/`**: Dockerfile (base CUDA devel, clone
   `PrismML-Eng/llama.cpp` branch `prism` em commit pinado, build `llama-server`
   para sm_86) + script `build.sh`. A imagem pinada garante a regra do fork:
   **nunca stock** — kernels ternários + Hadamard.
4. **Migração Bonsai**: `mv /home/jocic/bonsai-llm/models/Ternary-Bonsai-2-27B-gguf
   → models/`; diretório antigo mantido como referência mínima (fork + AGENTS.md)
   até confirmação do usuário; depois opcionalmente removido.
5. **Strata**: `strata/` no repo com Dockerfile (adaptado do upstream) e
   `README` próprio com os passos de instalação futura (RAM 31 GB → Coder,
   modelo em `/home`, NVMe); entry comentada no `config.yaml`.
6. **docker-compose.yml**: remover serviço `llama-cpp` (e volume do `models.ini`).
   Demais serviços intocados.
7. **Documentação**: `README.md` (novo perfil de uso single-user + fluxo),
   `DOCKER.md` (mudanças no compose), `AGENTS.md` (modelos, llama-swap, engine
   Bonsai), `models/MODELS_INSTALL.md` (Bonsai, path novo).

## Escopo

- Não baixa o modelo Strata (~70 GB) nem o MTP do Bonsai (~7 GB).
- Não altera open-webui/open-terminal/searxng/openwa.
- Validação de VRAM do Bonsai @64k é empírica; se OOM, entry cai para contexto
  menor com nota no config.
- Paralelismo: entries default `np=1`; exemplos `np=2` apenas comentados.

## Contexto

- `docker-compose.yml` — remove `llama-cpp`.
- `models/models.ini` — fonte dos parâmetros a traduzir; será desativado.
- `manage.sh` — reescrito para llama-swap.
- `/home/jocic/bonsai-llm/` — origem dos GGUFs e referência do fork (`prism`,
  commit `84445367f`).
- llama-swap: https://github.com/mostlygeek/llama-swap (config YAML, ttl, cmd).
- Strata: https://github.com/Niko1221/Strata (Dockerfile oficial, env `MODEL`/
  `FAMILY`/`CONTEXT`).

## Critérios de conclusão

- `curl http://localhost:8081/v1/models` lista os modelos stock + Bonsai.
- Request a um modelo stock e depois ao Bonsai faz o swap (modelo anterior descarregado).
- Bonsai PTQ1_0 responde (texto e, se testado, imagem via mmproj).
- `./manage.sh start|stop` gerencia o llama-swap corretamente.
- `docker compose config` válido sem o serviço `llama-cpp`.
- Docs (README, DOCKER.md, AGENTS.md, MODELS_INSTALL.md) sincronizadas, com o
  posicionamento single-user explícito.

## Questões abertas

- VRAM exata do Bonsai PTQ1_0 com ctx 65536 + mmproj (validar; fallback 49152).
- Se o usuário quiser remover `/home/jocic/bonsai-llm` após migração confirmada.

## Tasks

Índice (ordem de execução; detalhes em `.opencode/tasks/llama-swap-multi-engine/`):

| # | Task | Depende de | Estado |
|---|------|------------|--------|
| 001 | [llama-swap instalação + manage.sh](../../tasks/llama-swap-multi-engine/001-llama-swap-instalacao-manage-sh.md) | — | fechada (9,5/10) |
| 002 | [config.yaml stock + tradução models.ini](../../tasks/llama-swap-multi-engine/002-config-yaml-stock.md) | 001 | fechada (9/10) |
| 003 | [Engine Docker PrismML (fork pinado)](../../tasks/llama-swap-multi-engine/003-engine-prismml.md) | — | fechada (9/10) |
| 004 | [Migração GGUFs Bonsai + entries bonsai](../../tasks/llama-swap-multi-engine/004-migracao-bonsai.md) | 002, 003 | fechada (9/10) |
| 005 | [Infra Strata (Dockerfile + entry comentada)](../../tasks/llama-swap-multi-engine/005-strata-infra.md) | 002 | resolvida por subtasks (mãe 6/10 corrigir; 005-1 fechada 9/10) |
| 005-1 | [Correção — Strata `MODEL=IQ1_M` + textos README/Dockerfile](../../tasks/llama-swap-multi-engine/005-1-correcao-strata-env-model.md) | 005 | fechada (9/10) |
| 006 | [Compose: remover serviço llama-cpp](../../tasks/llama-swap-multi-engine/006-compose-remove-llama-cpp.md) | 004 | fechada (9,5/10) |
| 007 | [Validação end-to-end](../../tasks/llama-swap-multi-engine/007-validacao-e2e.md) | 004, 005, 006 | resolvida por subtasks (mãe 8/10 corrigir; 007-1 8/10 corrigir; 007-2 fechada 9,5/10) |
| 007-1 | [Correção — registro 007: flake exit 125, timings, limitações](../../tasks/llama-swap-multi-engine/007-1-correcao-registro-flake-exit-125.md) | 007 | resolvida por subtasks (8/10 corrigir; 007-2 fechada 9,5/10) |
| 007-2 | [Correção — Observação 007: alegações universais "sempre" do flake](../../tasks/llama-swap-multi-engine/007-2-correcao-alegacoes-universais-flake.md) | 007-1 | fechada (9,5/10; executor trocado para sorgan-qwen/qwen3.8-flash-next após bloqueio do sd2; entrega 9deb99f) |
| 008 | [Documentação (README, DOCKER, AGENTS, MODELS_INSTALL)](../../tasks/llama-swap-multi-engine/008-documentacao.md) | 007 | fechada (9,5/10; quórum 3/3 fechar — sd2/GLM-5.3-Flash indisponível (8083), substituído por openai/gpt-6-luna; A1 retirado pela revisora; entrega 9248db5) |

Nota: a 008 ganha escopo da revisão da 007 — documentar nas docs do repo o
flake `exit 125` recorrente entre sessões/modelos na carga pós-restart
(auto-recuperado pelo retry em parte das ocorrências; nas demais, sucesso só
em sessão posterior; causa indeterminada — hipótese de container órfão
enfraquecida pela assepsia em `logs/llama-swap.log:35-36`) e a limitação das
entries `PE_T2I/I2I_Heretic` listadas sem GGUF em disco.

Cobertura dos critérios de conclusão: models list (002/004), swap (002/004),
Bonsai responde (004), manage.sh (001), compose válido (006), docs
(008); bateria final consolidada em 007.
