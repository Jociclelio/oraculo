# Task 008: Sincronização de documentação (README, DOCKER.md, AGENTS.md, MODELS_INSTALL.md)

Estado: aguardando revisão
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
- Modelo: sorgan-qwen/qwen3.8-flash-next (execução retomada; a entrega 9248db5
  foi commitada pela execução anterior, interrompida por limite de contexto
  antes do registro — esta retomada apenas verificou a entrega e escreve o
  registro, sem reimplementar nem editar os docs)
- Base: a8cb25f
- Entrega: 9248db5 (9248db58056ace11bac3393fa484f6489114df0c; `git show --stat`
  confirma exatamente os 4 arquivos: README.md, DOCKER.md, AGENTS.md,
  models/MODELS_INSTALL.md — 623 inserções / 325 remoções)
- Arquivos da entrega: README.md, DOCKER.md, AGENTS.md, models/MODELS_INSTALL.md
- Evidências (verificação por grep pontual na entrega, sem leituras volumosas):
  - C1 ✅ — llama-swap/8081/manage.sh presentes nos 4 docs (contagens rg:
    README 33, DOCKER 48, AGENTS 54, MODELS_INSTALL 17). Remanescentes de
    `llama-cpp` só em contexto histórico/negativo ("antigo serviço removido",
    "sem o antigo llama-cpp"; `api_key="llama-cpp-local"` é só string de
    exemplo do cliente OpenAI). DOCKER.md:5,35,38 — serviço e mount
    `models.ini` declarados removidos; serving como processo de host.
  - C2 ✅ — README.md:36-37 "Posicionamento: stack para 1 usuário por vez" +
    seção dedicada "Single-user — paralelismo só como exceção" (README:153-156,
    `np>1` só exceção); ecoado no AGENTS.md (posicionamento plano).
  - C3 ✅ — AGENTS.md:97 seção "Engine Bonsai dedicada — regra **nunca
    stock**"; pin `84445367f` (AGENTS.md:104-105, SHA completo + build falha
    se HEAD ≠ pin); entries `bonsai-27b` (primária PTQ1_0+mmproj) e
    `bonsai-27b-pq2_0` (secundária) na tabela AGENTS.md:242-243.
  - C4 ✅ — MODELS_INSTALL.md:104,108-112 — GGUFs Bonsai em
    `models/Ternary-Bonsai-2-27B-gguf/` via `hf download
    prism-ml/Ternary-Bonsai-2-27B-gguf`; :129 nota "MTP do Bonsai não foi
    baixado"; :139-144 seção "Strata — não baixado" (~58 GB, entry comentada).
  - C5 ✅ — números batem com 007: ctx efetivo 65536, prefill ≈ 540 tok/s,
    decode ≈ 24,5 tok/s, VRAM 9146 MiB processo / 10657/12288 total
    (AGENTS.md:248-254; README.md:42-43; MODELS_INSTALL.md:249 ~9,1 GiB).
    O valor 10250 MiB da entry PQ2_0 (AGENTS.md:243) é a evidência da task
    004 (004-migracao-bonsai.md:93), corretamente atribuído à secundária.

## Notas

### Dificuldade esperada
2/10 — escrita documental a partir de um stack já validado; único cuidado é
não deixar seções antigas contraditórias.

### Dificuldade sentida
2/10 — escrita documental a partir de stack já validado, como esperado. A
entrega (9248db5) foi produzida pela execução anterior, que estourou o limite
de contexto (131072) por leituras volumosas antes do registro; a retomada foi
leve (verificação por grep pontual + registro), sem reimplementação. Único
cuidado real: não deixar seções antigas contraditórias — resolvido marcando
`models.ini`/`llama-cpp` como histórico em vez de apagar.

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
