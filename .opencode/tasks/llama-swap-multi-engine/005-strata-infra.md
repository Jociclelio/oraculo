# Task 005: Infra Strata — strata/ com Dockerfile adaptado + entry desabilitada

Estado: pendente
Depende de: 002
Origem: nenhuma

## Prompt

Preparar a infraestrutura do **Strata (Qwen3.8-Flash-Next)** sem baixar o
modelo (~70 GB — fora de escopo):

1. Criar `strata/Dockerfile` adaptado do Dockerfile oficial do upstream
   (https://github.com/Niko1221/Strata), preservando as env `MODEL`,
   `FAMILY` e `CONTEXT`.
2. Criar `strata/README.md` com os passos de instalação futura, incluindo os
   requisitos do plano: RAM 31 GB para a variante Coder, modelo a armazenar
   em `/home` (NVMe), e o comando/entry de ativação.
3. Adicionar ao `llama-swap/config.yaml` a entry do Strata **desabilitada
   (comentada)**, com `MODEL=coder`, `FAMILY=coder` e o `CONTEXT` alvo, com
   comentário apontando para `strata/README.md`.
4. Validar apenas o que não exige o modelo: `docker build` da imagem do
   Strata conclui (sem baixar pesos) e o YAML do config continua parseável
   (`./manage.sh start` + `curl /v1/models` continua funcionando; Strata NÃO
   deve aparecer na lista por estar comentado).

Restrições: não baixar o modelo Strata; não alterar entries existentes.

## Contexto

- `strata/` — novo diretório no repo.
- `llama-swap/config.yaml` — config da task 002/004; entry comentada aqui.
- https://github.com/Niko1221/Strata — Dockerfile oficial e semântica das env
  `MODEL`/`FAMILY`/`CONTEXT`.

## Corretude

- [ ] C1 — `docker build strata/` conclui sem baixar pesos do modelo.
- [ ] C2 — `llama-swap/config.yaml` contém a entry Strata comentada com
  `MODEL=coder` / `FAMILY=coder`; `curl http://localhost:8081/v1/models` não
  lista Strata.
- [ ] C3 — `strata/README.md` documenta RAM (31 GB), path do modelo em `/home`
  (NVMe) e passos de ativação futuros.
- [ ] C4 — Config continua válido após a edição (llama-swap sobe e responde).

## Execução
- Modelo:
- Base:
- Entrega:
- Arquivos da entrega:
- Evidências:

## Notas

### Dificuldade esperada
3/10 — adaptação de Dockerfile upstream e documentação; sem runtime para
validar de fato (modelo não baixado), risco baixo.

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
