# Task 002: config.yaml do llama-swap — macro stock + tradução do models.ini

Estado: pendente
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

- [ ] C1 — `curl http://localhost:8081/v1/models` lista todos os modelos stock
  traduzidos do `models.ini` (15 entries, com aliases `pe-t2i`/`pe-i2i`
  respeitados).
- [ ] C2 — Request de chat a dois modelos distintos funciona e o segundo swap
  descarrega o primeiro (verificado via `docker ps` sem container do primeiro
  modelo ou log do llama-swap mostrando stop do anterior).
- [ ] C3 — Entry MTP do Gemma (`Gemma4_12B_MTP`) carrega com `-ctkd f16
  -ctvd f16` e `spec-type draft-mtp` (conferir flags no log do container).
- [ ] C4 — Modelo MoE (ex. `Qwen3.6_35B_Code`) responde com `-ncmoe 28` visível
  no log de carga.
- [ ] C5 — Após ~300 s sem uso, o modelo ativo é descarregado (ttl funcionando).

## Execução
- Modelo:
- Base:
- Entrega:
- Arquivos da entrega:
- Evidências:

## Notas

### Dificuldade esperada
5/10 — tradução paramétrica extensa (15 seções) e sintaxe de macro/cmd do
llama-swap pouco familiar; validação empírica de cada entry é demorada
(carregamento de modelos grandes).

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
