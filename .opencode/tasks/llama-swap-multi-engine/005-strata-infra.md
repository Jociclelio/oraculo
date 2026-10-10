# Task 005: Infra Strata — strata/ com Dockerfile adaptado + entry desabilitada

Estado: aguardando revisão
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

- [x] C1 — `docker build strata/` conclui sem baixar pesos do modelo.
- [x] C2 — `llama-swap/config.yaml` contém a entry Strata comentada com
  `MODEL=coder` / `FAMILY=coder`; `curl http://localhost:8081/v1/models` não
  lista Strata.
- [x] C3 — `strata/README.md` documenta RAM (31 GB), path do modelo em `/home`
  (NVMe) e passos de ativação futuros.
- [x] C4 — Config continua válido após a edição (llama-swap sobe e responde).

## Execução
- Modelo: GLM-5.3-Flash (`sd2/GLM-5.3-Flash`), via agente task-executor (OpenCode)
- Base: `706c07b` (árvore limpa, branch `main`)
- Entrega: `f450e4c` — feat: infra Strata — Dockerfile adaptado (commit pinado
  61b3fb5, sm_86) + entry desabilitada no config.yaml
- Arquivos da entrega:
  - `strata/Dockerfile` (novo, 110 linhas) — adaptado do upstream
    Niko1221/Strata; clone pinado em `61b3fb5dd3f1e8ec09cf7e4e05208bc6d3c46406`
    (tip de main em 2026-10-10) com verificação dura; env `MODEL`/`FAMILY`/
    `CONTEXT` preservadas como defaults explícitos (`coder`/`coder`/`65536`),
    sobrescrevíveis via `-e`; `CUDA_ARCHITECTURES=86` (RTX 3060) em vez do
    binário gordo 75;80;86;89;120 do upstream
  - `strata/build-engine.py` (novo, 30 linhas) — corpo do heredoc upstream
    extraído para arquivo (ver dificuldade sentida)
  - `strata/README.md` (novo, 87 linhas) — requisitos (RAM 31 GB p/ Coder,
    modelo em /home NVMe, ~70 GB), build, run e ativação no llama-swap
  - `llama-swap/config.yaml` (19 inserções, diff puramente aditivo; entries
    existentes byte-idênticas — restrição respeitada)
- Evidências:
  - C1 — `docker build -t strata ./strata` concluiu (imagem 13,1 GB; 16 steps).
    Verificação dura pós-build dentro do container: `/opt/strata/engine/` com
    `strata` (57 MB) + `strata-vision` (73 MB) e `BUILD.json` (source=local,
    version 0.1.42, archs [86], vision gpu); `git rev-parse HEAD` =
    `61b3fb5…`; envs `MODEL=coder FAMILY=coder CONTEXT=65536` presentes. Zero
    ocorrências de download de pesos no log (grep huggingface/.gguf/"70 GB" → 0;
    únicos downloads: imagem base, apt, pip, clones git de Strata + llama.cpp).
  - C2 — Entry Strata 100% comentada no config (nome incluso), com
    `MODEL=coder`, `FAMILY=coder`, `CONTEXT=65536`, mount
    `/home/jocic/strata-data:/data` e comentário apontando para
    `strata/README.md`. `curl /v1/models` após restart: 17 entries, nenhuma
    com "strata" (case-insensitive; `grep -i strata` no JSON → vazio).
  - C3 — README contém: RAM 31 GB para Coder (com nota de que é a única
    variante que cabe nos 32 GB), modelo em `/home/jocic/strata-data` (NVMe
    XPG Gammix S70, justificativa de performance), comando `docker build`,
    comando `docker run` de primeiro start (download ~70 GB retomável) e
    passos de ativação da entry no llama-swap.
  - C4 — `./manage.sh stop && ./manage.sh start` + `curl /v1/models`: proxy
    subiu e respondeu com o config editado (17 entries); log do llama-swap sem
    erro de parse após o restart (WARNs presentes são de sessões anteriores).
- Notas de implementação:
  - **Armadilha do heredoc** (ver dificuldade): o 1º build com heredoc
    "concluiu" sem compilar nada — builder Docker local (sem buildx) não
    suporta heredoc; o RUN passou com python lendo stdin vazio (exit 0) e a
    imagem saía SEM engine. Detectado inspecionando `/opt/strata/engine/`
    (inexistente) numa imagem supostamente boa; corrigido com
    `strata/build-engine.py` + `COPY` + `RUN`. O Dockerfile documenta a
    adaptação e o porquê.
  - O CLI docker local não tem `--progress` nem `docker buildx` (wrapper
    legado apesar de reportar server 29.8.2) — builds seguem o parser clássico.
  - `FAMILY=coder` → tag de config `coder-coder` no volume (`strata-coder-coder.json`),
    comportamento correto do entrypoint upstream para família ≠ qwen.
  - Validação de runtime do Strata (carga do modelo, API em :8080) NÃO feita —
    depende do download de ~70 GB, fora de escopo (task 007 cobre o E2E na
    lista de presença, não no runtime).

## Notas

### Dificuldade esperada
3/10 — adaptação de Dockerfile upstream e documentação; sem runtime para
validar de fato (modelo não baixado), risco baixo.

### Dificuldade sentida
5/10 — o trabalho base (adaptar Dockerfile, README, entry comentada) foi direto
e abaixo do esperado (3/10), mas o heredoc do Dockerfile upstream criou uma
falha silenciosa séria: o build "concluía com sucesso" sem compilar a engine
(builder local sem buildx não suporta heredoc; python com stdin vazio sai 0).
Só foi detectada porque inspecionei o conteúdo da imagem em vez de confiar no
"Successfully built" — sem isso, a task entregaria uma imagem quebrada com C1
marcado como aprovado. Corrigir exigiu diagnóstico (docker sem buildx/--progress),
extração do script para arquivo e rebuild completo (~25 min).

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
