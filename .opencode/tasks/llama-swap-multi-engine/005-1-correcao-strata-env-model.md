# Task 005-1: Correção — Strata `MODEL=IQ1_M` + textos README/Dockerfile

Estado: aguardando revisão
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

- [x] C1 — `MODEL=IQ1_M` presente nos três artefatos com `FAMILY=coder` e
  `CONTEXT=65536` mantidos; `grep -rn "MODEL=coder" strata/ llama-swap/` →
  vazio.
- [x] C2 — Contraprova segura na imagem reconstruída: `docker run --rm
  --entrypoint sh strata -c '.venv/bin/python setup.py --setup --family coder
  --model coder --context 65536 --data-dir /tmp/probe --no-start'` continua
  falhando com exit 2 (regressão de semântica do upstream) e a leitura do dict
  `MODELS` dentro da imagem confirma `IQ1_M` como choice válido com
  `families=("coder",)`. NÃO executar `--model IQ1_M` com `--setup`.
- [x] C3 — `docker build -t strata ./strata` conclui após as edições sem
  baixar pesos (engine + `BUILD.json` presentes; `/data` vazio; resíduo
  `build-engine.py` ausente se item 5 aplicado).
- [x] C4 — Config continua parseável e válido: `yaml.safe_load` OK;
  `./manage.sh stop && ./manage.sh start` + `curl http://localhost:8081/v1/models`
  → 17 entries, Strata ausente; entries existentes byte-idênticas.
- [x] C5 — README e comentários do Dockerfile corrigidos: nenhuma afirmação
  de que Q2_0/IQ2_XS cabem em 32 GB; tamanho do Coder ≈ 58–65 GB; semântica
  FAMILY/MODEL correta.

## Execução
- Modelo: GLM-5.3-Flash (sd2/GLM-5.3-Flash)
- Base: 5a3b272 (branch main, árvore limpa)
- Entrega: 97936eb ("fix: Strata MODEL=IQ1_M (par correto FAMILY=coder) — corrigir defeito latente da 005")
- Arquivos da entrega: `strata/Dockerfile`, `strata/README.md`,
  `llama-swap/config.yaml`
- Evidências:
  - **C1** — `grep -rn "MODEL=coder" strata/ llama-swap/` → vazio (exit 1);
    `MODEL=IQ1_M` presente nos três artefatos com `FAMILY=coder` e
    `CONTEXT=65536` mantidos.
  - **C2** — na imagem reconstruída: `setup.py --setup --family coder --model
    coder ... --no-start` → exit 2 com `invalid choice: 'coder' (choose from
    'Q2_0', 'IQ2_XS', 'IQ3_XXS', 'IQ3_S', 'IQ1_M', 'UD-Q4_K_XL', 'UD-IQ4_XS')`;
    leitura do dict dentro da imagem confirma
    `MODELS['IQ1_M'] = {download_gb: 58.4, ram_gb: 32, arena_gb: 23.4,
    families: ('coder',)}` (sem executar `--model IQ1_M` com `--setup`).
  - **C3** — `docker build -t strata ./strata` concluiu (imagem
    `6d78b80de0f3`, ~25 min, sem download de pesos): `engine/strata`
    (57,9 MB), `engine/strata-vision` (73,4 MB), `engine/BUILD.json`
    (v0.1.42, archs [86]); `/data` vazio; resíduo `build-engine.py` ausente
    (item 5 aplicado: `rm -f` no mesmo RUN do build).
  - **C4** — `yaml.safe_load` OK; `./manage.sh stop && ./manage.sh start` +
    `curl http://localhost:8081/v1/models` → 17 entries, Strata ausente;
    `git diff` do config.yaml mostra alteração apenas no bloco comentado do
    Strata (entries ativas byte-idênticas).
  - **C5** — README sem claim de Q2_0/IQ2_XS em 32 GB (agora: 37,6/39,2 GB de
    RAM+VRAM, ou modo low-RAM com GPU de 24 GB); Coder ≈ 58 GB (~65 GB com
    MTP), conferido com `download_gb: 58.4` do upstream; semântica
    FAMILY/MODEL corrigida no comentário do Dockerfile; "~70 GB" substituído
    por "~58 GB" em todos os artefatos.
  - Limitações: contraprova do primeiro start real (download ~58 GB) não
    executada, por restrição da task (rebuild + validação de argparse/dict
    cobrem o defeito); editais cosméticos pós-build (comentário do Dockerfile
    e README) não afetam a imagem já reconstruída (nenhuma instrução de build
    alterada após o build).

## Notas

### Dificuldade esperada
2/10 — edições pontuais de env/textos em três arquivos + rebuild local já
dominado pela mãe; validação por regressão de argparse e parse YAML.

### Dificuldade sentida
2/10 — edições pontuais em três arquivos com spec clara; único atrito foi a
verificação inicial de engine/BUILD.json em caminho errado (`/opt/strata/`
em vez de `engine/`), resolvido com `find`; rebuild dominado pela mãe.

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
