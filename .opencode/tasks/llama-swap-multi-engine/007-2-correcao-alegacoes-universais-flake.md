# Task 007-2: Correção — Observação 007: alegações universais "sempre" do flake

Estado: bloqueada
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

- [ ] C1 — Os dois "sempre" da Observação (auto-recuperação e primeira carga)
  foram substituídos por texto fiel ao log, com referências de linha
  verificadas pelo executor antes da reescrita (recuperações reais: 121→122,
  140-143→144; falhas sem recuperação na sessão: shutdown após 15/17, 23/25,
  36/37, 49/50, 105; exceção da primeira carga: 121).
- [ ] C2 — Follow-up registra a evidência de assepsia (`log:35-36`) como
  enfraquecimento da hipótese de conflito de nome; causa segue marcada como
  indeterminada.
- [ ] C3 — Nenhuma outra alegação universal/não qualificada sobre o flake
  permanece (grep por "sempre" no arquivo fora de citações históricas e da
  seção Revisão da mãe); Dificuldade sentida e Limitações seguem coerentes.
- [ ] C4 — Diff toca **apenas** o `.md` da 007; checkboxes C1–C3 da Corretude
  e a seção Revisão da mãe inalterados; nenhum arquivo funcional; nenhum
  comando de carga/restart/benchmark/docker executado.

## Execução
- Modelo: <identificador real do executor>
- Base: <SHA completo antes da implementação>
- Entrega: <SHA(s) completos, sem commits de registro, ou sem alteração de artefatos>
- Arquivos da entrega: <paths ou referência ao diff dos commits>
- Evidências: <comandos/procedimentos, resultados e limitações>

## Notas

### Dificuldade esperada
1/10 — correção textual pontual (duas frases + uma linha de follow-up) com
verificação prévia de linhas de log já mapeadas; sem execução de stack.

### Dificuldade sentida
_/10 —

### Revisão
- Orquestrador: task-master (sorgan-qwen/qwen3.8-flash-next)
- Alvo: base `8e7f990` (HEAD; árvore limpa, sem stash, sem artefatos de tentativas
  anteriores). Sem entrega — a execução não foi iniciada.
- Avaliações: nenhuma rodada de revisão — não há entrega a avaliar.
- Nota final: —/10 (provisória; nada executado)
- Parecer: **bloqueio ambiental documentável.** A task é puramente documental e
  executável, mas o executor do ciclo (`sd2/GLM-5.3-Flash`) está indisponível: o
  endpoint do provider `http://localhost:8083/v1` (túnel SSH `-L 127.0.0.1:8083 →
  uranus.lsc.ic.unicamp.br:8080`, pid 644989, ativo desde 14:37) aceita a conexão
  e fecha sem resposta (`curl (56) Recv failure: Conexão fechada pela outra
  ponta`, 3 tentativas consecutivas; `/v1/models` → HTTP 000). O checkpoint do
  ciclo registra a tentativa anterior interrompida pelo mesmo `APIError`
  retryável em `localhost:8083`. Sem `alternate_executor_model` configurado; a
  troca de executor exige decisão do usuário (via `resume`/`config`), e a
  substituição silenciosa pela `task` nativa é proibida no ciclo. Nenhuma
  execução, nenhuma revisão, nenhum artefato produzido; nada a reverter.
- Decisão: bloqueada
- Reversão: não se aplica — sem entrega.
- Próximo passo: resolver o impedimento — (a) restabelecer o serviço remoto do
  sd2 (`uranus.lsc.ic.unicamp.br:8080`) mantendo o executor, ou (b) autorizar
  outro `executor_model` — e então `resume` do ciclo nesta mesma task. Atenção:
  a família 006 está em 4/5 tentativas; se a troca/continuação exigir nova
  tentativa além do limite, aumentar `max_family_attempts` no `resume`. A 008
  permanece travada até o fechamento da 007-2 (mãe 007 vira "resolvida por
  subtasks" ao fechar).

<!-- task-cycle: {"decision":"bloqueada","next_task":null,"family":".opencode/tasks/llama-swap-multi-engine/006-compose-remove-llama-cpp.md","plan":".opencode/plans/llama-swap-multi-engine/plan.md"} -->

Plano: [plan.md](../../plans/llama-swap-multi-engine/plan.md)
