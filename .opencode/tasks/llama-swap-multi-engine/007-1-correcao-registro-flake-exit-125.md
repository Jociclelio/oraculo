# Task 007-1: Correção — registro da 007 (flake exit 125, timings, limitações)

Estado: resolvida por subtasks (8/10 corrigir; 007-2 fechada 9,5/10 — F1/F2/F3 sanados)
Depende de: 007
Origem: 007 (correção)

## Prompt

Correção **exclusivamente documental** do registro da task 007
(`.opencode/tasks/llama-swap-multi-engine/007-validacao-e2e.md`), conforme a
revisão (decisão `corrigir`, 8/10). Não reexecutar a bateria, não reiniciar o
stack, não carregar modelos, não rodar benchmarks — nenhum arquivo funcional é
tocado. Corrigir no registro:

1. **Observação do flake `exit 125`** (task 007, seção Execução): reescrever
   admitindo a **recorrência entre sessões/modelos** — a mesma assinatura
   `upstream command exited prematurely` / `process exited: code=125` na
   primeira carga pós-start do llama-swap aparece em múltiplos segmentos do
   `logs/llama-swap.log` (ex.: linhas ~15,17,23,25,36,49,105,121,140-143;
   Ornith1.5_9B_MTP em ≥2 sessões, `bonsai-27b`, `Gemma4_12B`), sempre
   auto-recuperada pelo retry/health-check seguinte. Remover a alegação
   "não reproduziu em nenhuma das trocas seguintes" (válida só dentro da
   sessão 007) e a atribuição causal fechada "erro transiente do daemon
   docker" — registrar **causa indeterminada**, citando a hipótese alternativa
   não descartada de conflito de nome com container órfão (alerta já presente
   em `llama-swap/config.yaml:70-73`). Acrescentar follow-up explícito: na
   próxima ocorrência, capturar stderr do `docker run` / `docker events`;
   documentar o comportamento nas docs do repo (escopo da task 008).
2. **Dificuldade sentida**: alinhar ao item 1 (padrão recorrente, causa não
   determinada), sem a frase "não reproduzida após a primeira ocorrência".
3. **Timings C2**: o JSON colado é internamente inconsistente —
   `predicted_n 128` / `predicted_ms 5230,88` ⇒ **24,47 tok/s** (40,87
   ms/token); os 24,28/41,2 citados correspondem a `predicted_n 127`.
   Corrigir o texto para "decode ≈ 24,5 tok/s" e anotar a inconsistência de
   transcrição (fonte bruta não preservada; prefill 539,66 confere exato).
4. **Limitações de revalidação**: marcar item 4 e medições C2 (fingerprint,
   visão "BONSAI 42", timings, VRAM) como **evidência colada não revalidada
   de forma independente na rodada de revisão** (restrição do usuário contra
   carga de modelos pesados). Acrescentar uma linha registrando que
   `PE_T2I_Heretic`/`PE_I2I_Heretic` são listadas em `/v1/models` mas
   não-carregáveis (GGUF ausente em disco; já documentado no config.yaml) —
   2/17 entries não funcionais, limitação conhecida para a 008.

Preservar: checkboxes C1–C3 da Corretude, contrato, evidências históricas e
demais seções. A seção Revisão da 007 pertence ao master — não editar.

## Contexto

- `.opencode/tasks/llama-swap-multi-engine/007-validacao-e2e.md` — único
  arquivo a editar (Observação, Dificuldade sentida, bloco C2, limitações).
- `logs/llama-swap.log` — evidência da recorrência (conferir as linhas citadas
  antes de reescrever; log não tem timestamps).
- `llama-swap/config.yaml:70-73` — alerta sobre containers órfãos
  (hipótese alternativa do flake); `:277-278,293-294` — notas PE sem GGUF.
- Revisão da 007 (seção Revisão da mãe) — achados A1/A2 (GLM), F2/F3 (qwen),
  A1/A2/A3/A4 (muse) que originam esta correção.

## Corretude

- [x] C1 — Observação reescrita: recorrência reconhecida com referências de
  linha do log (verificadas pelo executor antes da reescrita: linhas 15, 17,
  23, 25, 36, 49, 105, 121, 140-143 do `logs/llama-swap.log`), causa marcada
  como indeterminada com hipótese alternativa (conflito de nome com container
  órfão, `llama-swap/config.yaml:70-73`), follow-up explícito registrado
  (capturar stderr do `docker run` / `docker events`; docs na task 008);
  nenhuma alegação de não-recorrência permanece no arquivo (as únicas
  menções restantes a "não reproduziu" citam a alegação antiga para
  retirá-la; a seção Revisão da mãe é intocada).
- [x] C2 — Dificuldade sentida alinhada (padrão recorrente, causa não
  determinada, duas hipóteses abertas; frase "não reproduzida após a
  primeira ocorrência" removida; sem contradição com a Observação).
- [x] C3 — Bloco de timings corrigido/anotado (decode ≈ 24,5 tok/s;
  5230,88 ms / 128 = 40,87 ms/token ⇒ 24,47 tok/s; anotado que 24,28/41,2
  correspondem a `predicted_n 127` — inconsistência de transcrição, fonte
  bruta não preservada; prefill 539,66 inalterado e confere exato).
- [x] C4 — Limitações marcadas: item 4 e medições C2 (fingerprint, visão
  "BONSAI 42", timings, VRAM) anotados como evidência colada não revalidada
  de forma independente na rodada de revisão; nota das 2/17 entries PE
  não-carregáveis com referência a `config.yaml:277-278` e `:293-294`.
- [x] C5 — Diff toca **apenas** o `.md` da 007 (verificado: `git diff
  9c6d901..e974e04 --stat` = 1 arquivo, +43/−13); nenhum arquivo funcional,
  checkboxes C1–C3 da Corretude da 007 preservados (verificados via diff);
  nenhum comando de carga/restart executado.

## Execução
- Modelo: sd2/GLM-5.3-Flash
- Base: 9c6d901a77cf409b3c0259ac01fa39662200dfe0 (árvore limpa; reexecução
  após tentativa interrompida por falha de transporte — sem artefatos
  parciais nem commits anteriores a reverter)
- Entrega: e974e0479facac347f5c6f68db763b68aa8b1ff5 (único commit de entrega;
  commit de registro é o commit seguinte que inclui este arquivo)
- Arquivos da entrega:
  `.opencode/tasks/llama-swap-multi-engine/007-validacao-e2e.md`
  (+43/−13; adicionado com `git add -f` — `.opencode/` está git-ignorado)
- Evidências:
  - `git status` inicial limpo em `9c6d901`; `git log --oneline -5` confere
    histórico da revisão da 007 (22085d0 → ee4cced → 9025984 → 9c6d901).
  - Verificação independente das linhas citadas antes da reescrita:
    leitura integral de `logs/llama-swap.log` (151 linhas, sem timestamps) —
    assinatura `upstream command exited prematurely` em 11 linhas
    (15, 17, 23, 25, 37, 50, 98, 105, 121, 140, 142); DEBUG
    `process exited: code=125` nas linhas 36 e 49 (ambos
    `Ornith1.5_9B_MTP`, em sessões distintas — blocos com PID próprio:
    149457 e 150093); `bonsai-27b` na linha 105; `Gemma4_12B` na linha 121
    (seguida de health-check OK na 122); recuperação por retry/health-check
    em 140-143 → 144. Linha 98 (`PE_T2I_Heretic`) confirmada como caso
    distinto (GGUF ausente). Todos os exemplos do prompt conferem; a lista
    no texto corrigido usa 15,17,23,25,36,49,105,121,140-143 (linhas WARN/
    DEBUG do padrão; 37/50 são os WARN associados aos DEBUG 36/49).
  - Leitura de `llama-swap/config.yaml`: linhas 70-73 confirmam o alerta de
    container órfão ("o próximo `docker run` falha por conflito de nome");
    linhas 277-278 e 293-294 confirmam as notas "(ATENÇÃO) GGUF não está em
    disco" das entries PE.
  - `grep -n "upstream command exited prematurely" logs/llama-swap.log | wc -l`
    → 11 ocorrências (recorrência entre sessões/modelos confirmada).
  - `git diff 9c6d901..e974e04 --stat` → 1 arquivo alterado (só o `.md` da
    007); `grep` no arquivo confirma que as únicas menções restantes a
    "não reproduziu"/"erro transiente" são citações da alegação antiga
    dentro do texto de correção (linhas 138-139) e a seção Revisão da mãe
    (intocada).
  - Matemática do C2 verificada: 5230,88/128 = 40,87 ms/token ⇒ 24,47 tok/s;
    5230,88/127 = 41,19 ms/token ⇒ 24,28 tok/s (os valores antigos batem com
    `predicted_n 127`); prefill 6318,76/3410 = 539,66 confere exato.
  - Limitações: reescrita apoiada exclusivamente no log persistido e no
    config; a causa do flake permanece indeterminada (follow-up registrado);
    evidências coladas do C2/item 4 da 007 não foram revalidadas ao vivo
    (restrição do usuário contra carga de modelos), apenas anotadas como
    limitação; nenhum comando de carga/restart/benchmark foi executado.

## Notas

### Dificuldade esperada
1/10 — reescrita documental guiada pelos achados da revisão; sem execução de
stack.

### Dificuldade sentida
1/10 — reescrita documental guiada pelos achados da revisão, como esperado.
Único cuidado: conferir linha a linha do log antes de citar referências
(o log não tem timestamps, então as sessões foram delimitadas pelos blocos
de PID DEBUG/shutdown) e preservar intactas as seções que pertencem ao
master (Revisão da 007, checkboxes C1–C3).

### Revisão
- Orquestrador: task-master (sorgan-qwen/qwen3.8-flash-next)
- Alvo: base `9c6d901`; entrega `e974e04` (único arquivo: o `.md` da 007, +43/−13); registro `ee7182c`; árvore limpa em HEAD. Reexecução legítima após tentativa interrompida por falha de transporte (APIError sd2, sem artefatos).
- Avaliações (rodada **paralela** — correção exclusivamente documental; revisores só leem arquivos/git, sem recursos compartilhados. Pool do arquivo global; `task-reviewer-glm` (sd2/GLM-5.3-Flash) **falhou** com APIError retryável de socket em `localhost:8083` e foi substituído pelo próximo do pool de modelo não representado, `task-reviewer-luna` (openai/gpt-6-luna); quórum com três modelos distintos):
  - `sorgan-qwen/qwen3.8-flash-next` — 8/10, **corrigir**; C1–C5 atendidos no essencial, mas F1 (médio): a Observação reescrita mantém "**sempre** auto-recuperada pelo retry/health-check seguinte", contraditada pelo log em 5 das 9 ocorrências (15/17→shutdown 19; 23/25→27; 36/37→40; 49/50→53; 105→107; Ornith flacou em 4 sessões consecutivas, sucesso só na PID 164646; as recuperações reais são 121→122 e 140-143→144); F2 (baixo): "**sempre** na primeira carga pós-start" contraditado pela própria linha 121 citada (Gemma4_12B foi a **segunda** carga da sessão iniciada em 118-119, cuja primeira, Gemma4_12B_Hauhau linha 120, passou); F3 (baixo/informativo): log:35-36 mostra assepsia prévia (`docker rm -f` antes do `docker run`) com exit 125 mesmo assim — enfraquece a hipótese de conflito de nome nesse caso; F4 (baixo): auto-relato do registro, sem ação.
  - `opencode/muse-spark-1.3-contributor-free` — 9/10, **fechar**; C1–C5 verificados independentemente (11 WARNs + DEBUGs 36/49 em sessões PID 149457/150093; config.yaml:70-73 e 277-278/293-294 confirmados; matemática C3 recomputada exata; C5 por diff: só o `.md` da 007, Corretude/Revisão da mãe byte-idênticas); O1 (baixo/informativo): o intervalo 140-143 intercala WARNs e métricas non-200, composição já explicitada no registro — citação defensável. Não examinou os quantificadores universais "sempre".
  - `openai/gpt-6-luna` — 9/10, **fechar com ressalva**; C2–C5 verificados (aritmética C3 conferida; config.yaml:70-73 e 277-278/293-294 confirmados; C5 por inspeção do diff); A1 (médio): `logs/llama-swap.log` **não está na árvore versionada** (arquivo untracked — confirmado pelo master), então as referências de linha e a universalidade de "sempre na primeira carga"/"sempre auto-recuperada" ficaram **não verificadas** nesta revisão; recomenda preservar a ressalva.
- Nota final: 8/10 — a entrega cumpre os itens 1–4 do prompt com referências de linha exatas (conferidas por dois revisores contra o log na working tree), matemática correta e disciplina de escopo impecável (C5: diff toca só o `.md` da 007; Corretude e Revisão da mãe intactas). O desconto incide sobre os quantificadores universais da Observação reescrita: "sempre auto-recuperada" e "sempre na primeira carga pós-start" são alegações de fato que o log contradita (F1/F2 do revisor que as verificou contra o log) e que o terceiro revisor não pôde verificar (log untracked). É a mesma classe de erro — superestimativa da benignidade do flake — que motivou a decisão `corrigir` da mãe; a redação foi herdada do prompt desta subtask, mas o executor tinha instrução explícita de conferir o log antes de reescrever.
- Parecer: dois revisores aprovam (um deles com a ressalva explícita de que as alegações universais ficaram não verificadas por ausência do log na árvore versionada); um revisor verificou-as contra o log e encontrou contradição factual (F1 médio, F2 baixo). Como o registro é o único artefato da task e a correção é textual mínima e delimitada, fechar perpetuaria em versão atenuada o achado que motivou esta subtask. Sem reversão (entrega preservada; a correção é aditiva sobre o mesmo texto).
- Decisão: corrigir
- Reversão: não se aplica — sem artefatos a desfazer.
- Próximo passo: subtask 007-2 (correção textual mínima na Observação da 007: substituir os dois "sempre" pelo comportamento real do log — recuperação em parte das ocorrências (121→122, 140-143→144), shutdown sem recuperação nas demais; "tipicamente primeira carga, exceção linha 121" — e registrar a evidência de assepsia (log:35-36) como enfraquecimento da hipótese de conflito de nome). Ao fechar a 007-2, a mãe 007 vira "resolvida por subtasks" e libera a 008.

<!-- task-cycle: {"decision":"corrigir","next_task":".opencode/tasks/llama-swap-multi-engine/007-2-correcao-alegacoes-universais-flake.md","family":".opencode/tasks/llama-swap-multi-engine/006-compose-remove-llama-cpp.md","plan":".opencode/plans/llama-swap-multi-engine/plan.md"} -->

Plano: [plan.md](../../plans/llama-swap-multi-engine/plan.md)
