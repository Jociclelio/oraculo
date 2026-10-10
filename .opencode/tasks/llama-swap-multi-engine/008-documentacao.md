# Task 008: Sincronização de documentação (README, DOCKER.md, AGENTS.md, MODELS_INSTALL.md)

Estado: pendente
Depende de: 007
Origem: nenhuma

## Prompt

Atualizar toda a documentação do repo para o novo stack, conforme a regra do
AGENTS.md ("qualquer mudança deve ser descrita nos arquivos correspondentes"):

1. **README.md** — novo perfil de uso: substituição do container `llama-cpp`
   pelo llama-swap; posicionamento explícito **stack para 1 usuário por vez**
   (entradas paralelas `np>1` só como exceção pontual para modelos pequenos);
   meta de prefill/decode razoável com contexto ≥ 64k (128k quando VRAM e
   prefill permitirem); fluxo `./manage.sh start|stop` atualizado; engines
   stock/Bonsai/Strata.
2. **DOCKER.md** — remoção do serviço `llama-cpp` e do mount `models.ini`;
   nota de que o serving passou a ser processo de host (fora do compose).
3. **AGENTS.md** — seção llama-swap (porta 8081, config.yaml, ttl ≈ 300 s,
   reescrita do manage.sh, `bin/`+`logs/`), tabela de modelos apontando para
   o config YAML, engine Bonsai dedicada (`engines/llama.cpp-prismml/`,
   regra **nunca stock** — kernels ternários + Hadamard, commit pinado
   `84445367f`), Bonsai PTQ1_0 como entry primária e PQ2_0 secundária, infra
   Strata preparada (entry comentada), remoção da doc do `models.ini`
   desativado.
4. **models/MODELS_INSTALL.md** — novos GGUFs Bonsai em
   `models/Ternary-Bonsai-2-27B-gguf/` (origem `prism-ml/Ternary-Bonsai-2-27B-gguf`
   via `hf download`), path novo; nota sobre MTP do Bonsai não baixado.
5. Marcar/desativar a documentação do `models.ini` como histórica (não
   apagar conteúdo de referência sem necessidade — os parâmetros agora vivem
   comentados no config.yaml).

Basear os textos nos **resultados reais** das evidências da task 007 (ctx
efetivo do Bonsai, VRAM medida), não em estimativas.

## Contexto

- `README.md` — guia de uso; seções do llama-cpp a reescrever.
- `DOCKER.md` — doc do compose; reflete serviço removido.
- `AGENTS.md` — doc de modelos/serviços; seções `models.ini` e `llama-cpp` a
  substituir.
- `models/MODELS_INSTALL.md` — guia de instalação de modelos.
- `llama-swap/config.yaml` — fonte da verdade dos parâmetros/entries.
- `engines/llama.cpp-prismml/`, `strata/` — novas pastas a documentar.

## Corretude

- [ ] C1 — Os 4 arquivos citam o llama-swap, a porta 8081 e o fluxo
  `manage.sh` atual, sem remanescentes de instruções de subir o container
  `llama-cpp` como modo ativo.
- [ ] C2 — Posicionamento single-user explícito no README (e ecoado onde
  relevante).
- [ ] C3 — AGENTS.md registra a regra "nunca stock" da engine Bonsai, o pin
  `84445367f` e as entries `bonsai-27b` / `bonsai-27b-pq2_0`.
- [ ] C4 — MODELS_INSTALL.md aponta o novo path dos GGUFs Bonsai e o estado
  do Strata (não baixado).
- [ ] C5 — Números documentados (ctx, VRAM) batem com as evidências da task
  007.

## Execução
- Modelo:
- Base:
- Entrega:
- Arquivos da entrega:
- Evidências:

## Notas

### Dificuldade esperada
2/10 — escrita documental a partir de um stack já validado; único cuidado é
não deixar seções antigas contraditórias.

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
