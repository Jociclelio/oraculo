# Task 005-1: Correção — Strata `MODEL=IQ1_M` + textos README/Dockerfile

Estado: pendente
Depende de: 005
Origem: 005 (correção)

## Prompt

Corrigir o defeito latente no caminho de ativação do Strata entregue na task
005 (`f450e4c`), preservando todo o resto da entrega (build, pin, estrutura —
aprovados na revisão da mãe):

1. Trocar `MODEL=coder` por `MODEL=IQ1_M` nos três artefatos: default `ENV`
   do `strata/Dockerfile`, passo de `docker run`/ativação do `strata/README.md`
   e entry comentada do `llama-swap/config.yaml`. Manter `FAMILY=coder` e
   `CONTEXT=65536`.
2. Corrigir o comentário de semântica no Dockerfile: `FAMILY` = variante
   (`qwen`/`swift`/`coder`/`unsloth`); `MODEL` = tamanho/quant (`Q2_0`…
   `IQ1_M`); a família `coder` só tem a size `IQ1_M`.
3. Corrigir o `strata/README.md`: (a) remover/retificar a afirmação de que
   Q2_0/IQ2_XS "cabem" em 32 GB de RAM — o upstream exige ~44–46 GB de RAM
   para essas variants, ou modo low-RAM com GPU de 24 GB (não é o caso:
   RTX 3060 12 GB); (a linha "é a única variante que cabe" é a correta);
   (b) ajustar o tamanho do download da variante Coder: IQ1_M ≈ 58,4 GB
   (~65 GB com MTP), não "~70 GB".
4. Reconstruir a imagem (`docker build -t strata ./strata`) para manter a
   imagem consistente com o Dockerfile editado (build local ~25 min, parte do
   fluxo; sem download de pesos). Aproveitar o mesmo layer para o item 5.
5. Opcional (baixo): remover o resíduo `build-engine.py` da imagem
   (ex.: `rm -f build-engine.py` no mesmo `RUN` que executa o build).

Motivação (confirmado por duas contraprovas independentes na revisão da mãe):
o `setup.py` do upstream valida `--model` com `choices=list(MODELS)` e o
`docker-entrypoint.sh` repassa `--model "$MODEL"` cru; `coder` é chave de
`FAMILIES`, não de `MODELS` — o primeiro start com `MODEL=coder` falha com
`invalid choice: 'coder'` (exit 2) antes de qualquer download.

Restrições: NÃO baixar pesos nem executar `setup.py --setup` com model válido
(iniciaria download de ~58 GB); não alterar entries existentes do config; não
tocar em outros arquivos; não fazer push.

## Contexto

- `strata/Dockerfile` — default `ENV MODEL=coder` (~linha 55) e comentário de
  semântica FAMILY/MODEL (~linhas 44–46).
- `strata/README.md` — passos de run/ativação com `-e MODEL=coder` (~linhas
  52, 63–64) e claims de variantes/RAM (~linhas 23, 29).
- `llama-swap/config.yaml` — entry Strata comentada (~linhas 342–358).
- `.opencode/tasks/llama-swap-multi-engine/005-strata-infra.md` — mãe; seção
  Revisão com as evidências da contraprova (argparse exit 2, MODELS/FAMILIES).
- Upstream: https://github.com/Niko1221/Strata @ `61b3fb5dd3f1e8ec09cf7e4e05208bc6d3c46406`
  — `setup.py` (dicts `MODELS`/`FAMILIES`; `IQ1_M` é a única size com
  `families=("coder",)`, 58,4 GB), `docker-entrypoint.sh` (repassa as envs
  cruas), `docs/MODELS.md` (requisitos de RAM por variante).

## Corretude

- [ ] C1 — `MODEL=IQ1_M` presente nos três artefatos com `FAMILY=coder` e
  `CONTEXT=65536` mantidos; `grep -rn "MODEL=coder" strata/ llama-swap/` →
  vazio.
- [ ] C2 — Contraprova segura na imagem reconstruída: `docker run --rm
  --entrypoint sh strata -c '.venv/bin/python setup.py --setup --family coder
  --model coder --context 65536 --data-dir /tmp/probe --no-start'` continua
  falhando com exit 2 (regressão de semântica do upstream) e a leitura do dict
  `MODELS` dentro da imagem confirma `IQ1_M` como choice válido com
  `families=("coder",)`. NÃO executar `--model IQ1_M` com `--setup`.
- [ ] C3 — `docker build -t strata ./strata` conclui após as edições sem
  baixar pesos (engine + `BUILD.json` presentes; `/data` vazio; resíduo
  `build-engine.py` ausente se item 5 aplicado).
- [ ] C4 — Config continua parseável e válido: `yaml.safe_load` OK;
  `./manage.sh stop && ./manage.sh start` + `curl http://localhost:8081/v1/models`
  → 17 entries, Strata ausente; entries existentes byte-idênticas.
- [ ] C5 — README e comentários do Dockerfile corrigidos: nenhuma afirmação
  de que Q2_0/IQ2_XS cabem em 32 GB; tamanho do Coder ≈ 58–65 GB; semântica
  FAMILY/MODEL correta.

## Execução
- Modelo: <identificador real do executor>
- Base: <SHA completo antes da implementação>
- Entrega: <SHA(s) completos, sem commits de registro, ou sem alteração de artefatos>
- Arquivos da entrega: <paths ou referência ao diff dos commits>
- Evidências: <comandos/procedimentos, resultados e limitações>

## Notas

### Dificuldade esperada
2/10 — edições pontuais de env/textos em três arquivos + rebuild local já
dominado pela mãe; validação por regressão de argparse e parse YAML.

### Dificuldade sentida
_/10 —

### Revisão
- Orquestrador: —
- Alvo: <SHAs da entrega e versão do registro revisado>
- Avaliações: <modelo A: _/10; modelo B: _/10; modelo C: _/10>
- Nota final: _/10
- Parecer: <síntese dos achados, evidências, divergências e Corretude pendente>
- Decisão: <fechar | corrigir | reiniciar | repartir; pendente se bloqueada>
- Reversão: <SHA ou não se aplica>
- Próximo passo: <subtasks em ordem ou próxima task liberada>

Plano: [plan.md](../../plans/llama-swap-multi-engine/plan.md)
