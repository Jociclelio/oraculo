# Task 002: config.yaml do llama-swap — macro stock + tradução do models.ini

Estado: fechada
Depende de: 001
Origem: nenhuma

## Prompt

Criar `llama-swap/config.yaml` com:

1. **Macro para modelos stock**: um comando Docker reutilizável que roda
   `ghcr.io/ggml-org/llama.cpp:full-cuda` com `--gpus all`, mount
   `./models:/models`, `llama-server --host 0.0.0.0 --port <porta-interna>`
   `-fa on --jinja`, e `ttl` ≈ 300 s (substitui `sleep-idle-seconds`). Usar o
   mecanismo de macro/cmd do llama-swap (ver docs do upstream) para que cada
   entry só declare o modelo e overrides.
2. **Uma entry por seção do `models.ini`** (todas as 15 seções de modelo,
   exceto as de Bonsai/Strata que não existem lá): traduzir cada parâmetro INI
   para a flag equivalente do llama-server (`ctx-size` → `-c`, `ngl` → `-ngl`,
   `n-cpu-moe` → `-ncmoe`, `mmproj` → `--mmproj`, `model-draft` +
   `spec-type`/`spec-draft-n-max` para MTP/DFlash, amostragem `temp/top-p/
   top-k/min-p/presence-penalty/repeat-penalty`, `batch-size`/`ubatch-size`,
   `cache-type-k/v` e variantes `-draft`, `cache-ram`, `alias`). Preservar
   comentários relevantes do INI como comentários no YAML (ex.: nota de OOM do
   ctx 262144 do Gemma MTP, aliases `pe-t2i`/`pe-i2i`).
3. **Paralelismo**: default `np=1`; incluir um exemplo comentado de `np=2`
   apenas como referência (posicionamento single-user do plano).
4. Validar o ciclo real: `./manage.sh start`, `curl
   http://localhost:8081/v1/models` listando os modelos, e um request de
   chat curto a pelo menos dois modelos distintos (um pequeno, ex. PE_T2I ou
   Ornith 9B, e um MoE 35B) confirmando que o swap descarrega o anterior
   (checar `docker ps` e/ou logs do llama-swap).

Restrições: não criar entries de Bonsai (task 004) nem Strata (task 005);
`models.ini` permanece no repo, desativado (remoção do serviço docker é a task
006); não alterar outros serviços do compose.

## Contexto

- `models/models.ini` — fonte única de parâmetros a traduzir (205 linhas, 15
  seções; caminhos `/models/...` continuam válidos pois o mount é o mesmo).
- `llama-swap/` — novo diretório; `config.yaml` vive aqui.
- `manage.sh` — criado na task 001, usado para subir o proxy.
- https://github.com/mostlygeek/llama-swap — sintaxe de `macros`, `cmd`, `ttl`,
  `proxy` e healthcheck no config.
- `docker-compose.yml` — referência do comando atual do container
  (`--models-preset --models-max 1`) para conferir equivalência de flags.

## Corretude

- [x] C1 — `curl http://localhost:8081/v1/models` lista todos os modelos stock
  traduzidos do `models.ini` (15 entries, com aliases `pe-t2i`/`pe-i2i`
  respeitados).
- [x] C2 — Request de chat a dois modelos distintos funciona e o segundo swap
  descarrega o primeiro (verificado via `docker ps` sem container do primeiro
  modelo ou log do llama-swap mostrando stop do anterior).
- [x] C3 — Entry MTP do Gemma (`Gemma4_12B_MTP`) carrega com `-ctkd f16
  -ctvd f16` e `spec-type draft-mtp` (conferir flags no log do container).
- [x] C4 — Modelo MoE (ex. `Qwen3.6_35B_Code`) responde com `-ncmoe 28` visível
  no log de carga.
- [x] C5 — Após ~300 s sem uso, o modelo ativo é descarregado (ttl funcionando).

## Execução
- Modelo: GLM-5.3-Flash (sd2/GLM-5.3-Flash)
- Base: 1a77409189be7a2295f2bb2aa0cba424ffe6c27d
- Entrega: fe352bd (feat: config.yaml do llama-swap — macro Docker stock + 15 modelos do models.ini)
- Arquivos da entrega: `llama-swap/config.yaml` (novo, 302 linhas)
- Evidências:
  - C1 ✔ — após `./manage.sh start`, `GET /v1/models` retorna as 15 entries
    (Gemma4_12B, Gemma4_12B_MTP, Qwen3.6_28B_A3B, Qwen3.6_35B_General,
    Qwen3.6_35B_General_VL, Qwen3.6_35B_Code, Qwen3.6_35B_It_General,
    Qwen3.6_35B_It_Reasoning, Ornith1.5_9B_MTP, Ornith1.5_9B_DFlash,
    Ornith1.5_35B_MTP, Gemma4_12B_Hauhau, Qwen3.6_35B_A3B_Hauhau_Aggressive,
    PE_T2I_Heretic, PE_I2I_Heretic) com aliases `pe-t2i`/`pe-i2i` no meta.
    Bonsai/Strata ausentes, conforme restrição.
  - C2 ✔ — chat em `Ornith1.5_9B_MTP` (resposta OK, finish=length por
    max_tokens) e depois em `Qwen3.6_35B_Code` (resposta OK): `docker ps`
    antes = `ls-Ornith1.5_9B_MTP`, depois = `ls-Qwen3.6_35B_Code`; log do
    llama-swap: `evicting [Ornith1.5_9B_MTP]` + `process stopped ... exit
    status 137` (cmdStop `docker rm -f`).
  - C3 ✔ — `docker inspect ls-Gemma4_12B_MTP` mostra no Cmd: `--model-draft
    .../mtp-gemma-4-12B-it.gguf`, `--spec-type draft-mtp`, `-ctkd f16`,
    `-ctvd f16`; log do container: draft carregado e MTP ativo
    (`draft acceptance = 0.64220`), `n_ctx_slot = 64000`.
  - C4 ✔ — `docker inspect ls-Qwen3.6_35B_Code` Cmd contém `-ncmoe 28`; log de
    carga: `tensor overrides to CPU are used` (override MoE aplicado); resposta
    gerada (150 tokens, MoE 35B com experts na CPU).
  - C5 ✔ — após 310 s de ociosidade com `Gemma4_12B_MTP` carregado: container
    removido (`docker ps` vazio de `ls-*`), log `sending stop signal ... exit
    status 137` (unload por ttl), VRAM de volta ao baseline (622 MiB).
  - Observação de ambiente: container `llama-cpp` do compose já estava
    `Exited` antes dos testes (porta 8081 livre); nenhum serviço do compose foi
    alterado. `manage.sh stop` ao final (llama-swap não fica rodando após a
    task; o fluxo de uso sobe com `./manage.sh start`).

### Desvios técnicos registrados (não alteram escopo)

1. **Entrypoint da imagem**: `ghcr.io/ggml-org/llama.cpp:full-cuda` tem
   ENTRYPOINT `/app/tools.sh` (dispatcher que espera `-s`); o macro usa
   `--entrypoint /app/llama-server` para chamar o binário diretamente.
2. **cmd sem shell**: o llama-swap tokeniza `cmd`/`cmdStop` com shlex — não há
   shell; `;`, pipes e redirecionamentos viram argumentos (causou exit 125 no
   primeiro teste). `cmdStop: docker rm -f ls-${MODEL_ID}` é um comando único
   determinístico; cleanup manual de órfãos: `docker rm -f ls-<Modelo>`.
3. **Caminho do Qwen 28B** (retificado na revisão): o INI na base já aponta
   `Qwen3.6-28B-REAP20-A3B-Q4_K_M/` (models.ini:52), igual ao disco — não houve
   "correção vs INI"; a comparação original foi com a tabela do AGENTS.md. O
   caminho usado no YAML está correto; o comentário no config.yaml (linha ~98)
   deve ser ajustado como ride-along na task 008.
4. **PE Heretic**: GGUFs não estão em disco (`models/pe_*_heretic-Q4_K_M/`
   vazios) — entries mantidas com nota; aparecem no `/v1/models` mas não
   carregam até os arquivos serem baixados (não é escopo desta task).
5. **-ngl 99** usado para `ngl = all` (convenção do próprio INI).
6. Requisitos de saúde do proxy: `healthCheckTimeout: 300` para cobrir carga a
   frio dos GGUFs de ~21 GB.

## Notas

### Dificuldade esperada
5/10 — tradução paramétrica extensa (15 seções) e sintaxe de macro/cmd do
llama-swap pouco familiar; validação empírica de cada entry é demorada
(carregamento de modelos grandes).

### Dificuldade sentida
6/10 — a tradução paramétrica em si foi direta (o INI até documenta o comando
equivalente do Gemma MTP), mas três pegadinhas consumiram tempo: (1) o
ENTRYPOINT `/app/tools.sh` da imagem full-cuda rejeita `llama-server` como
comando; (2) o llama-swap v263 executa `cmd` sem shell (shlex), o que proíbe
`;`/pipes/redirecionamentos e descarta o prefixo idempotente de cleanup — o
erro só aparecia como "exit 125" opaco; (3) um container órfão segurando a
porta 5805 mascarou a correção durante a depuração. Descoberta relevante
registrada: o stop padrão por SIGTERM ao client docker anexado funciona
(container para e --rm remove), mas optei por `cmdStop: docker rm -f` por ser
determinístico.

### Revisão
- Orquestrador: GLM-5.3-Flash (sd2/GLM-5.3-Flash), agente task-master
- Alvo: base 1a77409; entrega fe352bd (llama-swap/config.yaml, novo, 302 linhas);
  registro 113c43b; árvore limpa; isolamento confirmado (só config.yaml + task md).
- Modo da rodada: sequencial — a verificação C1–C5 pode disputar recursos
  compartilhados (GPU, porta 8081, Docker); revisores rodaram um por vez.
- Pool: `.opencode/task-reviewer-pool.md`; sem falhas, sem substituições.
- Avaliações:
  1. task-reviewer-glm (sd2/GLM-5.3-Flash) — 8,5/10 — estático; tradução
     seção a seção fiel (15/15), sintaxe validada contra upstream (macros,
     ttl, healthCheckTimeout, strip de `#` em cmd); achados: A1 desvio #3
     impreciso (menor), A2 `#` dentro de cmd dependente do upstream (info).
  2. task-reviewer-qwen-flash (sorgan-qwen/qwen3.8-flash-next) — 9/10 —
     conferência parâmetro a parâmetro das 15 entries + flags validadas no
     --help do llama-server do build da imagem; C1 reproduzido dinamicamente
     (15 entries + aliases em meta); achados: F1 desvio #3 falso (`git log -S`
     não acha o caminho "errado"), F3 `--verbosity` não traduzido (cosmético),
     F4 comentário mmproj do 28B não preservado (baixo), F5 mount relativo
     depende do CWD do manage.sh (info).
  3. task-reviewer-muse (opencode/muse-spark-1.3-contributor-free) — 9/10 —
     C1 reproduzido de forma independente (binário v263 + cópia do config em
     porta isolada, sem tocar GPU); C2/C5 comprovados por log em disco
     (`evicting`/exit 137; `TTL of 300s reached`); C3/C4 flags confirmadas no
     cmd real do log; achados: A1 desvio #3 inexistente (baixo), A2 falhas
     intermediárias de debug coerentes (baixo), A3 PE Heretic esperado (baixo).
- Síntese: consenso de aprovação nos três pareceres. Tradução INI→YAML fiel em
  todas as 15 entries, mecanismos do llama-swap (macro, cmdStop, ttl,
  healthCheckTimeout, strip de comentários) verificados contra o upstream v263
  por dois revisores independentes; evidências dinâmicas C1–C5 coerentes entre
  executor e logs em disco, com C1 reproduzido por dois revisores. Única
  inconsistência real é documental: o desvio #3 (retificado acima) — o caminho
  do Qwen 28B nunca diferiu do INI. Ajuste do comentário no config.yaml
  (linha ~98) e tradução de `--verbosity`/comentário mmproj ficam como
  ride-along na task 008 (docs); não justificam ciclo de correção.
- Nota final: 9/10 — entrega completa e validada (C1–C5 comprovados, em parte
  por verificação independente), isolamento perfeito; desconto pela imprecisão
  documental do desvio #3 e pequenos detalhes cosméticos de tradução.
- Parecer: aprovada — todos os critérios obrigatórios comprovados.
- Decisão: fechar
- Reversão: não se aplica — sem artefatos a reverter
- Próximo passo: liberar task 003 (Engine Docker PrismML, fork pinado)

<!-- task-cycle: {"decision":"fechar","next_task":".opencode/tasks/llama-swap-multi-engine/003-engine-prismml.md","family":".opencode/tasks/llama-swap-multi-engine/003-engine-prismml.md","plan":".opencode/plans/llama-swap-multi-engine/plan.md"} -->

Plano: [plan.md](../../plans/llama-swap-multi-engine/plan.md)
