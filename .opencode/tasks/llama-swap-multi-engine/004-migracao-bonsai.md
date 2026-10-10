# Task 004: Migração dos GGUFs Bonsai + entries bonsai-27b no config.yaml

Estado: fechada
Depende de: 002, 003
Origem: nenhuma

## Prompt

Migrar os GGUFs do Bonsai 2 para o repo e expô-los via llama-swap usando a
imagem da task 003.

1. **Migração**: `mv /home/jocic/bonsai-llm/models/Ternary-Bonsai-2-27B-gguf
   → models/` (arquivos: `Ternary-Bonsai-2-27B-PTQ1_0.gguf` ~5.9 GB,
   `Ternary-Bonsai-2-27B-PQ2_0.gguf` ~7.2 GB,
   `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf` ~629 MB). O diretório antigo
   `/home/jocic/bonsai-llm` permanece no lugar como referência mínima (fork +
   AGENTS.md); **não remover** — remoção é decisão futura do usuário (questão
   aberta do plano).
2. **Entries no `llama-swap/config.yaml`** usando a imagem local
   `llama.cpp-prismml:latest` (mesmo padrão Docker do macro stock, mount
   `./models:/models`, `-fa on --jinja`, ttl ≈ 300 s):
   - `bonsai-27b` — **entry primária**: PTQ1_0 + mmproj, `-ngl 99`, ctx
     **65536 a validar**; se OOM na RTX 3060 (12 GB, ~880 MiB usados pelo
     display), cair para 49152 e deixar nota comentada no config documentando
     o fallback. Não definir temp/top-p/top-k: os defaults de sampling
     (thinking: temp 1.0, top_p 0.95, top_k 20) vivem nos metadados do GGUF.
   - `bonsai-27b-pq2_0` — entry secundária: PQ2_0 (default mais rápido em
     Ampere), mesmas diretrizes de ctx/validação.
   - Sem MTP (não baixado — fora de escopo).
3. **Validação empírica** (llama-swap rodando): request de chat a
   `bonsai-27b` responde texto coerente; conferir no log de carga do
   container que o modelo carregou como Bonsai (PTQ1_0, não Q2_0 legacy).
   Se houver mmproj testável, um request com imagem; se não testado, registrar
   limitação nas evidências.

Restrições: não alterar entries stock; não remover `/home/jocic/bonsai-llm`.

## Contexto

- `/home/jocic/bonsai-llm/models/Ternary-Bonsai-2-27B-gguf/` — origem dos 3
  GGUFs a mover.
- `/home/jocic/bonsai-llm/AGENTS.md` — smoke test de referência (expectativas:
  load OK, ~8 GB VRAM em PQ2_0 c/ ctx 4096; PTQ1_0 menor) e regra "nunca
  stock / Q2_0 legacy produz lixo".
- `llama-swap/config.yaml` — arquivo da task 002 onde as entries são
  adicionadas.
- `models/` — destino da migração (mesmo mount usado pelo macro Docker).

## Corretude

- [x] C1 — `ls models/Ternary-Bonsai-2-27B-gguf/` mostra os 3 GGUFs e
  `/home/jocic/bonsai-llm/models/Ternary-Bonsai-2-27B-gguf` não existe mais
  (movido, não copiado).
- [x] C2 — `curl http://localhost:8081/v1/models` inclui `bonsai-27b` e
  `bonsai-27b-pq2_0`.
- [x] C3 — Request de chat a `bonsai-27b` (PTQ1_0) responde texto coerente; o
  log de carga confirma PTQ1_0 (não Q2_0 legacy) e o ctx efetivo usado.
- [x] C4 — Swap stock → Bonsai descarrega o modelo anterior (container
  anterior some / log do llama-swap).
- [x] C5 — VRAM do PTQ1_0 com ctx escolhido + mmproj documentada nas
  evidências; se OOM, entry usa ctx fallback com nota no config.

## Execução
- Modelo: GLM-5.3-Flash (`sd2/GLM-5.3-Flash`), via agente task-executor (OpenCode)
- Base: `779fc16` (árvore limpa, branch `main`)
- Entrega: `b3f8ac2` — feat: entries bonsai-27b (PTQ1_0 + mmproj) e
  bonsai-27b-pq2_0 no config.yaml via imagem PrismML
- Arquivos da entrega:
  - `llama-swap/config.yaml` (macro `docker-prismml` + entries `bonsai-27b`,
    `bonsai-27b-pq2_0`; entries stock intocadas — diff só com adições,
    53 linhas)
- Evidências:
  - C1 — `mv` executado: `models/Ternary-Bonsai-2-27B-gguf/` contém os 3 GGUFs
    (`PTQ1_0` 5,6 GB, `PQ2_0` 6,8 GB, `mmproj-Q8_0` 601 MB; origem em
    `/home/jocic/bonsai-llm/models/` resta apenas `models.ini` — diretório de
    GGUFs não existe mais). `/home/jocic/bonsai-llm` preservado (AGENTS.md,
    fork, start.sh). `models/*` é gitignored → migração não gera commit git.
  - C2 — `./manage.sh start` + `curl /v1/models` lista as 17 entries, incluindo
    `bonsai-27b` e `bonsai-27b-pq2_0`.
  - C3 — Chat a `bonsai-27b`: resposta coerente ("A capital do Brasil é
    Brasília.", 46 tokens, ~26 tok/s gen; `system_fingerprint b1-8444536` =
    commit pinado do fork). `docker logs ls-bonsai-27b` confirma carga de
    `/models/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PTQ1_0.gguf`
    (não Q2_0 legacy) + mmproj carregado + `n_ctx_slot = 65536` (ctx efetivo).
  - mmproj testável e funcional: request com PNG vermelho 64×64 base64 →
    "Vermelho" (visão OK na entry primária).
  - C4 — Swap nas duas direções: `bonsai-27b` → `Ornith1.5_9B_MTP` (stock):
    container `ls-bonsai-27b` some, sobe `ls-Ornith1.5_9B_MTP`; volta
    stock → Bonsai: `ls-Ornith1.5_9B_MTP` removido (`exit 137` via
    `docker rm -f`, VRAM liberada) e `ls-bonsai-27b` responde HTTP 200.
  - C5 — VRAM observada (nvidia-smi, display incluso):
    `bonsai-27b` (PTQ1_0 + mmproj, ctx 65536): **9967 MiB / 12288** — sem OOM;
    `bonsai-27b-pq2_0` (PQ2_0, ctx 65536): **10250 MiB / 12288** — sem OOM.
    Fallback de ctx (49152) não foi necessário; nota de referência mantida no
    comentário da entry. PQ2_0 também validada com chat coerente
    ("A capital do Brasil é Brasília.").
- Notas de implementação:
  - Descoberta: a imagem `llama.cpp-prismml:latest` **herda o ENTRYPOINT**
    `nvidia_entrypoint.sh` da base `nvidia/cuda` (o Dockerfile da task 003 não
    o sobrescreve — a nota "sem ENTRYPOINT" valia só para CMD explícito). Com
    cmd começando em flags (`--host ...`), o entrypoint falha com
    `exec: --: invalid option` e o llama-swap reporta "upstream command exited
    prematurely". Corrigido no macro `docker-prismml` com
    `--entrypoint /usr/local/bin/llama-server` — mesmo padrão do macro stock.
    O Dockerfile da task 003 não foi alterado (fora do escopo desta task).
  - Avisos inofensivos no log do servidor: `cache_reuse is not supported by
    multimodal` (entry primária) e warning Qwen-VL sobre `--image-min-tokens`
    — sem impacto nos testes realizados.
  - Primeiro chat da PQ2_0 com `max_tokens=100` retornou content vazio
    (raciocínio consumiu o orçamento); com 300 tokens responde coerente —
    comportamento do modelo thinking, não da config.

## Notas

### Dificuldade esperada
4/10 — `mv` e entries YAML são simples; risco é a validação de VRAM
(empírica, pode exigir ajuste de ctx) e o tempo de carga dos modelos.

### Dificuldade sentida
3/10 — `mv` e entries YAML foram diretos; a única dificuldade real foi o
ENTRYPOINT herdado da base nvidia/cuda (falha críptica "upstream command exited
prematurely" antes de o log mostrar o erro real), resolvida com o mesmo padrão
`--entrypoint` do macro stock. Validação de VRAM não exigiu fallback de ctx —
menos ajuste empírico do que o previsto na dificuldade esperada (4/10).

### Revisão
- Orquestrador: task-master (sorgan-qwen/qwen3.8-flash-next)
- Alvo: base `779fc16` → entrega `b3f8ac2` (feat, único arquivo
  `llama-swap/config.yaml`, 53 inserções puramente aditivas) + registro
  `e099473`; migração dos GGUFs fora do rastreio git (`models/*` ignorado —
  verificado no filesystem). Árvore limpa; config em disco idêntico a `b3f8ac2`.
  Modo da rodada: **paralelo** (revisão somente leitura de fontes/config/estado
  leve; sem disputa por recursos compartilhados), três sessões novas.
- Avaliações: `task-reviewer-glm` (sd2/GLM-5.3-Flash) **9/10 — fechar**;
  `task-reviewer-qwen-flash` (sorgan-qwen/qwen3.8-flash-next) **9/10 — fechar**;
  `task-reviewer-muse` (opencode/muse-spark-1.3-contributor-free) **7/10
  provisória — corrigir** na rodada inicial; após pedido de esclarecimento do
  orquestrador, **revisada para 8/10 — fechar** com ressalva registrada.
- Síntese: os três conferiram o alvo (SHAs, árvore limpa, diff puramente
  aditivo; entries/macros stock byte-idênticos à base — restrição respeitada).
  C1 e C2 comprovados diretamente por todos (3 GGUFs no destino, origem
  removida, `/v1/models` com as 17 entries). Lado PQ2_0 de C3/C5 comprovado ao
  vivo pelos três: container `ls-bonsai-27b-pq2_0` com o mesmo macro
  `docker-prismml`, `n_ctx_slot = 65536`, `nvidia-smi` 10250/12288 batendo
  exatamente com o alegado. A descoberta do ENTRYPOINT herdado da base
  nvidia/cuda foi confirmada independente (Qwen: `docker image inspect`; Muse:
  `--version` → commit pinado `8444536`) e o workaround `--entrypoint` no macro
  é correto e bem documentado. Divergência: Muse apontou (achados A5/A6) que as
  provas brutas do lado PTQ1_0 (log de carga, chat, visão, 9967 MiB, `exit 137`
  do swap) não são re-auditáveis — containers `--rm` por design e log em INFO.
  GLM (P1) e Qwen (A5) notaram a mesma lacuna mas a aceitaram como limitação
  de preservação de evidência, não defeito. Esclarecido pelo orquestrador com
  os fatos corroborantes (sequência de health checks 5815→5805→5815→5816 no
  `logs/llama-swap.log`, `docker ps` com um único container, macro idêntico
  transferindo entrypoint/ctx, entry apontando para PTQ1_0 no fork — stock
  recusaria), Muse mudou para fechar 8/10. **Ressalva registrada** (aceita
  pelos três): C3-chat/visão, C4-detalhe de evicção e C5-VRAM da primária
  permanecem relato calibrado do executor (PQ2_0 conferiu exato) + corroboração
  indireta, sem logs brutos persistidos; revalidação dispensada por custo
  (recarga de ~5,6 GB em GPU compartilhada). Achados não bloqueantes para
  follow-up futuro: comentário "Sem ENTRYPOINT/CMD" do Dockerfile da task 003
  é factualmente errado (A4/Qwen); `--cache-reuse 256` é ignorado pelo contexto
  PrismML/multimodal (cosmético); diretriz futura de persistir `docker logs`
  antes do `--rm` em validações (Muse).
- Nota final: 9/10 — entrega mínima, fiel ao prompt, restrições respeitadas e
  validação empírica sólida no que é verificável; a lacuna residual é de
  preservação de evidência (arquitetura `--rm`), não de defeito concreto.
- Parecer: aprovada. C1–C5 comprovados (C1/C2 diretos; C3/C4/C5 diretos no
  lado PQ2_0 e corroborados de forma independente no lado PTQ1_0, com a
  ressalva acima).
- Decisão: fechar
- Reversão: não se aplica — entrega preservada.
- Próximo passo: task 005 (Infra Strata — depende de 002, já fechada).

<!-- task-cycle: {"decision":"fechar","next_task":".opencode/tasks/llama-swap-multi-engine/005-strata-infra.md","family":".opencode/tasks/llama-swap-multi-engine/003-engine-prismml.md","plan":".opencode/plans/llama-swap-multi-engine/plan.md"} -->

Plano: [plan.md](../../plans/llama-swap-multi-engine/plan.md)
