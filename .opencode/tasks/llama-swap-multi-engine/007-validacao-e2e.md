# Task 007: Validação end-to-end do stack multi-engine

Estado: pendente
Depende de: 004, 005, 006
Origem: nenhuma

## Prompt

Executar a bateria completa de critérios de conclusão do plano contra o stack
final (sem alterações funcionais; correções pontuais encontradas durante a
validação são permitidas e devem ser registradas):

1. Reinício limpo: `./manage.sh stop && ./manage.sh start`.
2. `curl http://localhost:8081/v1/models` lista modelos **stock + Bonsai**
   (Strata ausente, comentado).
3. Request a um modelo stock e depois ao Bonsai confirma o **swap** (modelo
   anterior descarregado — `docker ps` / logs do llama-swap).
4. Bonsai **PTQ1_0** responde texto; testar também via mmproj com imagem se
   viável (registrar como evidência ou limitação).
5. `./manage.sh start|stop` idempotentes (start em duplicata avisa; stop sem
   processo não falha).
6. `docker compose config` válido sem `llama-cpp`.
7. Checagem de posicionamento: entries default `np=1`, exemplo `np=2` apenas
   comentado no config.

Se algum critério falhar por causa pequena de config/script, corrigir no
mesmo commit e revalidar; se a causa for estrutural, parar e reportar para o
task-master decidir (correção/reinício/repartição).

## Contexto

- `llama-swap/config.yaml` — resultado consolidado das tasks 002/004/005.
- `manage.sh`, `bin/llama-swap` — da task 001.
- `docker-compose.yml` — da task 006.
- `/home/jocic/bonsai-llm/AGENTS.md` — expectativas de performance do Bonsai
  (PQ2_0 ~35 tok/s gen, ~8 GB VRAM com ctx 4096) para sanidade dos números.

## Corretude

- [ ] C1 — Todos os critérios de conclusão do plano verificados e passando
  (lista acima C2–C7), com evidências coladas (outputs de curl, docker ps,
  trechos de log).
- [ ] C2 — Evidências incluem medição de VRAM/prefill/decode do Bonsai PTQ1_0
  no ctx escolhido (meta do plano: razoável com contexto ≥ 64k).
- [ ] C3 — Nenhuma regressão nos demais serviços (`docker compose ps` todos
  up; WebUI acessível na 8080).

## Execução
- Modelo:
- Base:
- Entrega:
- Arquivos da entrega:
- Evidências:

## Notas

### Dificuldade esperada
2/10 — execução de bateria de testes manuais; risco baixo, apenas tempo de
carga dos modelos.

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
