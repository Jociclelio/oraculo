# Task 007-2: Correção — Observação 007: alegações universais "sempre" do flake

Estado: fechada
Depende de: 007-1
Origem: 007-1 (correção)

## Prompt

Correção **exclusivamente documental e mínima** da Observação do flake `exit
125` no registro da task 007 (`.opencode/tasks/llama-swap-multi-engine/007-validacao-e2e.md`),
conforme a revisão da 007-1 (decisão `corrigir`, 8/10). Não reexecutar a
bateria, não reiniciar o stack, não carregar modelos, não rodar benchmarks —
nenhum arquivo funcional é tocado. A entrega da 007-1 (recorrência, causa
indeterminada, timings, limitações) está preservada; aqui só se corrigem duas
alegações de universalidade que o log contradita:

1. **"sempre auto-recuperada pelo retry/health-check seguinte"** (Observação
   da 007): substituir pelo comportamento real do `logs/llama-swap.log` —
   recuperação pelo retry/health-check **confirmada em parte das ocorrências**
   (ex.: 121→122; bloco 140-143→144); nas demais, o log mostra **shutdown da
   sessão após a falha, sem recuperação registrada** (pares 15/17→shutdown ~19;
   23/25→~27; 36/37→~40; 49/50→~53; 105→~107), com sucesso apenas em sessão
   posterior (Ornith1.5_9B_MTP flaca em sessões consecutivas antes de passar
   na sessão PID 164646). **Conferir cada linha citada no log antes de
   reescrever** — as linhas acima vêm do parecer do revisor, não de fonte
   versionada.
2. **"sempre na primeira carga pós-start do llama-swap"** (Observação da 007):
   substituir por "tipicamente na primeira carga de um modelo após o start",
   com a exceção real registrada: linha 121 (`Gemma4_12B`) foi a **segunda**
   carga da sessão iniciada em ~118-119, cuja primeira carga (`Gemma4_12B_Hauhau`,
   ~linha 120) passou sem falha.
3. **Follow-up do flake**: acrescentar a evidência de assepsia — `logs/llama-swap.log:35-36`
   mostra `docker rm -f ls-...` antes do `docker run` (remoção prévia do nome)
   e ainda assim `exit 125`, o que **enfraquece a hipótese de conflito de nome
   com container órfão nesse caso**. Manter a causa como **indeterminada**; a
   hipótese do órfão permanece aberta mas enfraquecida.

Preservar: todo o restante da Observação reescrita pela 007-1 (lista de
ocorrências, causa indeterminada, follow-up stderr/`docker events`, docs na
008), os checkboxes C1–C3 da Corretude da 007, a seção Revisão da 007 (do
master), as demais seções e os blocos de limitação/timings. Conferir que
Dificuldade sentida e o bloco "Limitação de revalidação" continuam sem
contradição com o novo texto.

## Contexto

- `.opencode/tasks/llama-swap-multi-engine/007-validacao-e2e.md` — único
  arquivo a editar (Observação do flake na seção Execução; checar
  consistência com Dificuldade sentida).
- `logs/llama-swap.log` — **untracked** (não está na árvore versionada;
  ler da working tree; 151 linhas, sem timestamps; sessões delimitadas por
  blocos start/shutdown e PIDs nos DEBUG). Verificar as linhas citadas acima
  antes de reescrever; ajustar as referências se diferirem.
- `.opencode/tasks/llama-swap-multi-engine/007-1-correcao-registro-flake-exit-125.md`
  — seção Revisão: achados F1 (médio), F2 (baixo) e F3 (informativo) que
  originam esta correção.
- Revisão da 007 (mãe) — contexto histórico; não editar.

## Corretude

- [x] C1 — Os dois "sempre" da Observação (auto-recuperação e primeira carga)
  foram substituídos por texto fiel ao log, com referências de linha
  verificadas pelo executor antes da reescrita (recuperações reais: 121→122,
  140-143→144; falhas sem recuperação na sessão: shutdown após 15/17, 23/25,
  36/37, 49/50, 105; exceção da primeira carga: 121). Todas as linhas do
  parecer conferidas no log antes da reescrita — nenhuma divergência
  (shutdowns exatos em 19/27/40/53/107; ver Evidências).
- [x] C2 — Follow-up registra a evidência de assepsia (`log:35-36`) como
  enfraquecimento da hipótese de conflito de nome; causa segue marcada como
  indeterminada (hipótese do órfão "aberta, porém enfraquecida").
- [x] C3 — Nenhuma outra alegação universal/não qualificada sobre o flake
  permanece (grep por "sempre" no arquivo: 1 ocorrência, linha 198, dentro da
  seção Revisão da mãe — exceção permitida); Dificuldade sentida e
  Limitações seguem coerentes (ver Evidências).
- [x] C4 — Diff toca **apenas** o `.md` da 007 (`git diff c86323a..9deb99f
  --stat` = 1 arquivo, +34/−20, hunks só na Observação); checkboxes C1–C3 da
  Corretude e a seção Revisão da mãe inalterados (verificados no diff);
  nenhum arquivo funcional; nenhum comando de carga/restart/benchmark/docker
  executado.

## Execução
- Modelo: sorgan-qwen/qwen3.8-flash-next (identidade real informada pelo
  runtime nesta sessão; o bloqueio anterior por indisponibilidade do executor
  `sd2/GLM-5.3-Flash` não se aplica — o master retomou esta task com executor
  distinto, modelo diferente do que redigiu a Observação rejeitada na 007-1)
- Base: c86323af2cc654f14b448f82f053d07eeed81128 (HEAD; `git status` árvore
  limpa, sem alterações preexistentes nem artefatos de tentativas anteriores)
- Entrega: 9deb99f3010561855e494c478868c76f99772c25 (único commit de entrega;
  o commit de registro é o commit seguinte que inclui este arquivo)
- Arquivos da entrega:
  `.opencode/tasks/llama-swap-multi-engine/007-validacao-e2e.md` (+34/−20;
  parágrafo da Observação do flake apenas; `git add -f` — `.opencode/` está
  git-ignorado, arquivo já tracked)
- Evidências:
  - `git status` inicial limpo em `c86323a`; `git log --oneline -5` confere o
    histórico (8e7f990 criou a 007-2; cb5aac0 é a revisão da 007-1 com
    F1/F2/F3).
  - Leitura integral de `logs/llama-swap.log` (151 linhas, untracked, sem
    timestamps; sessões delimitadas por blocos start/shutdown e PIDs DEBUG)
    **antes** da reescrita, mais greps de conferência — todas as linhas do
    parecer do revisor **confirmadas, sem divergências**:
    - `grep -n "upstream command exited prematurely"` → 11 WARNs (15, 17, 23,
      25, 37, 50, 98, 105, 121, 140, 142); `grep -n "process exited:
      code=125"` → DEBUG 36 e 49 (ambos Ornith1.5_9B_MTP).
    - Recuperações reais: 121 (WARN `Gemma4_12B`) → 122 (health check OK);
      140-143 (WARN/non-200 intercalados) → 144 (health check OK).
    - Shutdowns sem recuperação na sessão (`grep -n "shutting down"`): 15/17 →
      19; 23/25 → 27; 36/37 → 40; 49/50 → 53; 105 → 107 — exatamente as
      linhas estimadas pelo revisor (dispensou ajuste).
    - Ornith1.5_9B_MTP: 4 sessões consecutivas de falha (blocos 13-20 e
      21-28, sem PID registrado; PID 149457 na linha 29; PID 150093 na 42);
      sucesso apenas na sessão PID 164646 (PID na 55; health check na 63).
      `grep -n "PID:"` → 29, 42, 55.
    - Exceção da primeira carga: sessão iniciada em 118-119; primeira carga
      `Gemma4_12B_Hauhau` (120) passou; 121 (`Gemma4_12B`) é a segunda carga.
    - Assepsia: `grep -n "docker rm -f"` → só a linha 35
      (`docker rm -f ls-Ornith1.5_9B_MTP 2>/dev/null; docker run ...`) com
      `exit 125` na 36. Nuance observada no log e **não** acrescentada ao
      texto (fora do escopo mínimo): o prefixo de assepsia aparece apenas em
      35; os starts das linhas 48 e 61 rodam `docker run` sem `docker rm -f`.
  - C3: `grep -n -i "sempre" .opencode/tasks/llama-swap-multi-engine/007-validacao-e2e.md`
    → 1 ocorrência (linha 198), dentro da seção Revisão da mãe (parecer do
    master — exceção explícita do critério). Na Observação restam apenas
    formulações qualificadas ("tipicamente", "confirmada apenas em parte das
    ocorrências", "aberta, porém enfraquecida").
  - C4: `git diff c86323af2cc654f14b448f82f053d07eeed81128..9deb99f --stat` →
    1 arquivo (só o `.md` da 007); `git diff -U2` mostra um único hunk na
    Observação — Corretude C1–C3, Revisão da mãe, Dificuldade sentida, bloco
    "Limitação de revalidação" e timings byte-idênticos.
  - Coerência: Dificuldade sentida da 007 ("padrão recorrente; causa não
    determinada; hipóteses de transiente e de órfão permanecem abertas") segue
    compatível com o novo texto (órfão enfraquecida, não descartada); bloco de
    limitação de revalidação intocado e sem contradição.
  - Limitações: reescrita apoiada exclusivamente no log da working tree
    (untracked — não versionado, mesma ressalva da revisão da 007-1) e nos
    registros; nenhum comando docker/carga/restart/benchmark executado; a
    causa do flake segue indeterminada (follow-up preservado).

## Notas

### Dificuldade esperada
1/10 — correção textual pontual (duas frases + uma linha de follow-up) com
verificação prévia de linhas de log já mapeadas; sem execução de stack.

### Dificuldade sentida
2/10 — um ponto acima do esperado (1/10): a edição textual em si é trivial,
mas a verificação exigiu mapear o log sem timestamps linha a linha (9
ocorrências da assinatura, 5 shutdowns pós-falha, 3 sessões com PID, o par
118-121 da exceção e o caso de assepsia 35-36) antes de reescrever; todas as
referências do parecer conferiram exatas, sem ajustes. Cuidado adicional:
manter Revisão da mãe e Corretude C1–C3 intactas e validar o grep "sempre"
com a única exceção permitida.

### Revisão

#### Rodada 1 — bloqueio ambiental (histórico preservado, registro `c86323a`)
- Orquestrador: task-master (sorgan-qwen/qwen3.8-flash-next)
- Alvo: base `8e7f990`; sem entrega — a execução não foi iniciada.
- Parecer: **bloqueio ambiental documentável.** Executor do ciclo
  (`sd2/GLM-5.3-Flash`) indisponível: endpoint `http://localhost:8083/v1`
  (túnel SSH → `uranus.lsc.ic.unicamp.br:8080`) fechava conexões sem resposta
  (HTTP 000). Sem `alternate_executor_model`; troca exigia decisão do usuário.
- Decisão: bloqueada → **resolvida pelo usuário** via `resume`/`config` com
  `executor_model = sorgan-qwen/qwen3.8-flash-next` (opção (b) do encaminhamento).

#### Rodada 2 — rodada final (quórum completo)
- Orquestrador: task-master (sorgan-qwen/qwen3.8-flash-next)
- Alvo: base `c86323af2cc654f14b448f82f053d07eeed81128`; entrega `9deb99f3010561855e494c478868c76f99772c25`
  (único arquivo: `.md` da 007, +34/−20, hunk único só na Observação); registro
  `e4420638f282672c7d56573765a5b1a5c191ec0b`; executor `sorgan-qwen/qwen3.8-flash-next`
  (identidade real confirmada; 5ª/5 tentativa da família 006); árvore limpa em HEAD.
- Avaliações (rodada **paralela** — correção exclusivamente documental; revisores
  só leem arquivos/git, sem recursos compartilhados. Pool do arquivo global:
  `task-reviewer-glm` (sd2/GLM-5.3-Flash) **pulado** — endpoint `localhost:8083`
  ainda sem serviço remoto (HTTP 000 verificado antes da rodada; omissão
  registrada); quórum com três modelos distintos. Nota de transparência:
  `qwen3.8-flash-next` também é o modelo executor; a regra de quórum exige três
  revisores de modelos distintos entre si, e os outros dois são independentes do
  executor):
  - `sorgan-qwen/qwen3.8-flash-next` — 10/10, **fechar**; C1–C4 verificados
    independentemente contra o log da working tree (recuperações 121→122 e
    140-143→144; shutdowns exatos 19/27/40/53/107; PIDs 29/42/55; par 120/121;
    assepsia só na linha 35); positividade de "tipicamente" conferida (demais
    ocorrências são de fato primeira carga em suas sessões). A1 (baixo/
    informativo): a lista de linhas herdada da 007-1 (`007-validacao-e2e.md:144`)
    mistura WARNs da assinatura com DEBUGs 36/49 em vez dos WARNs pareados
    37/50 — preservada por instrução do prompt, não é defeito desta entrega.
    A2 (baixo/informativo): assepsia em apenas 1 de 3 starts (linhas 48/61 sem
    `docker rm -f`) — texto versionado escopa corretamente à sessão PID 149457,
    sem alegação de generalidade.
  - `opencode/muse-spark-1.3-contributor-free` — 9/10, **fechar**; C1–C4
    verificados (greps independentes das assinaturas, shutdowns e PIDs; diff
    byte-idêntico fora da Observação). O1 (baixo/informativo): "Dificuldade
    sentida" da 007 diz hipóteses "permanecem abertas" vs. Observação "aberta,
    porém enfraquecida" — coerente (enfraquecida ⊂ aberta), sem contradição.
  - `openai/gpt-6-luna` — 10/10, **fechar**; nenhum achado material; única
    ocorrência de "sempre" no arquivo é a linha 198, na Revisão da mãe
    (exceção permitida); causa segue corretamente indeterminada.
- Nota final: **9,5/10** — os dois universais rejeitados na 007-1 (F1 médio,
  F2 baixo) e o follow-up F3 foram sanados com texto fiel ao log e referências
  de linha exatas, reconfirmadas pelos três revisores por conta própria; escopo
  mínimo impecável (hunk único; Corretude C1–C3 e Revisão da mãe byte-idênticas;
  nenhum arquivo funcional; nenhuma execução de stack). O desconto não é defeito
  desta entrega: (a) o log de evidência é untracked — referências de linha não
  reproduzíveis a partir da árvore versionada (limitação inerente, já registrada
  e com escopo de documentação na 008); (b) a lista de linhas herdada da 007-1
  mistura WARN/DEBUG (A1), preservada por instrução explícita do prompt.
- Parecer: unânime 3/3 por fechar. Nenhuma divergência entre revisores; nada
  pendente de correção. Sem reversão (entrega preservada).
- Decisão: **fechar**
- Reversão: não se aplica — sem artefatos a desfazer.
- Próximo passo: mãe 007 e 007-1 viram "resolvida por subtasks" (mesmo commit
  documental); a 008 (Documentação) é liberada como próxima task principal e
  carrega o escopo do flake já anotado no plano, mais os achados A1 (lista de
  linhas mista, herdada) e A2 (assepsia em apenas 1 de 3 starts) desta rodada
  caso reescreva o flake nas docs do repo.

<!-- task-cycle: {"decision":"fechar","next_task":".opencode/tasks/llama-swap-multi-engine/008-documentacao.md","family":".opencode/tasks/llama-swap-multi-engine/006-compose-remove-llama-cpp.md","plan":".opencode/plans/llama-swap-multi-engine/plan.md"} -->

Plano: [plan.md](../../plans/llama-swap-multi-engine/plan.md)
