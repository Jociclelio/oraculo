# Task 007-1: Correção — registro da 007 (flake exit 125, timings, limitações)

Estado: pendente
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

- [ ] C1 — Observação reescrita: recorrência reconhecida com referências de
  linha do log, causa marcada como indeterminada com hipótese alternativa,
  follow-up explícito registrado; nenhuma alegação de não-recorrência
  permanece no arquivo.
- [ ] C2 — Dificuldade sentida alinhada (sem contradição com a Observação).
- [ ] C3 — Bloco de timings corrigido/anotado (decode ≈ 24,5 tok/s ou
  inconsistência explicitada; prefill inalterado).
- [ ] C4 — Limitações marcadas: C2/item 4 como evidência colada não
  revalidada; nota das 2 entries PE não-carregáveis.
- [ ] C5 — Diff toca **apenas** o `.md` da 007; nenhum arquivo funcional,
  nenhum checkbox C1–C3 da Corretude alterado; nenhum comando de carga/
  restart executado.

## Execução
- Modelo: <identificador real do executor>
- Base: <SHA completo antes da implementação>
- Entrega: <SHA(s) completos, sem commits de registro, ou sem alteração de artefatos>
- Arquivos da entrega: <paths ou referência ao diff dos commits>
- Evidências: <comandos/procedimentos, resultados e limitações>

## Notas

### Dificuldade esperada
1/10 — reescrita documental guiada pelos achados da revisão; sem execução de
stack.

### Dificuldade sentida
_/10 —

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
