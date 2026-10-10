# Task 007-1: Correção — registro da 007 (flake exit 125, timings, limitações)

Estado: aguardando revisão
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
- Orquestrador: —
- Alvo:
- Avaliações:
- Nota final: _/10
- Parecer:
- Decisão:
- Reversão:
- Próximo passo:

Plano: [plan.md](../../plans/llama-swap-multi-engine/plan.md)
