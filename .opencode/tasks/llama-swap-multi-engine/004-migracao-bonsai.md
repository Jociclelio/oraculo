# Task 004: Migração dos GGUFs Bonsai + entries bonsai-27b no config.yaml

Estado: pendente
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

- [ ] C1 — `ls models/Ternary-Bonsai-2-27B-gguf/` mostra os 3 GGUFs e
  `/home/jocic/bonsai-llm/models/Ternary-Bonsai-2-27B-gguf` não existe mais
  (movido, não copiado).
- [ ] C2 — `curl http://localhost:8081/v1/models` inclui `bonsai-27b` e
  `bonsai-27b-pq2_0`.
- [ ] C3 — Request de chat a `bonsai-27b` (PTQ1_0) responde texto coerente; o
  log de carga confirma PTQ1_0 (não Q2_0 legacy) e o ctx efetivo usado.
- [ ] C4 — Swap stock → Bonsai descarrega o modelo anterior (container
  anterior some / log do llama-swap).
- [ ] C5 — VRAM do PTQ1_0 com ctx escolhido + mmproj documentada nas
  evidências; se OOM, entry usa ctx fallback com nota no config.

## Execução
- Modelo:
- Base:
- Entrega:
- Arquivos da entrega:
- Evidências:

## Notas

### Dificuldade esperada
4/10 — `mv` e entries YAML são simples; risco é a validação de VRAM
(empírica, pode exigir ajuste de ctx) e o tempo de carga dos modelos.

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
