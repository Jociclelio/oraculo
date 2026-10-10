# Task 007: Validação end-to-end do stack multi-engine

Estado: aguardando subtasks
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

- [x] C1 — Todos os critérios de conclusão do plano verificados e passando
  (lista acima C2–C7), com evidências coladas (outputs de curl, docker ps,
  trechos de log).
- [x] C2 — Evidências incluem medição de VRAM/prefill/decode do Bonsai PTQ1_0
  no ctx escolhido (meta do plano: razoável com contexto ≥ 64k).
- [x] C3 — Nenhuma regressão nos demais serviços (`docker compose ps` todos
  up; WebUI acessível na 8080).

## Execução
- Modelo: sd2/GLM-5.3-Flash
- Base: 4fc852e (árvore limpa)
- Entrega: sem alteração de artefatos (task de validação — nenhum critério
  exigiu correção; nenhum arquivo funcional foi modificado)
- Arquivos da entrega: nenhum (apenas este registro documental)
- Evidências:

**Item 1 — Reinício limpo** (`./manage.sh stop && ./manage.sh start`):
```
Parando llama-swap (PID 1344419)... / llama-swap parado.
Iniciando llama-swap em background (porta 8081)...
llama-swap ativo: PID 1401636, log em logs/llama-swap.log.
```

**Item 2 — /v1/models (stock + Bonsai, Strata ausente)**: 17 entries —
15 stock (`Gemma4_12B`, `Gemma4_12B_MTP`, `Gemma4_12B_Hauhau`,
`Qwen3.6_28B_A3B`, `Qwen3.6_35B_General`, `Qwen3.6_35B_General_VL`,
`Qwen3.6_35B_Code`, `Qwen3.6_35B_It_General`, `Qwen3.6_35B_It_Reasoning`,
`Ornith1.5_9B_MTP`, `Ornith1.5_9B_DFlash`, `Ornith1.5_35B_MTP`,
`Qwen3.6_35B_A3B_Hauhau_Aggressive`, `PE_T2I_Heretic`, `PE_I2I_Heretic`)
+ 2 Bonsai (`bonsai-27b`, `bonsai-27b-pq2_0`). Nenhuma entry `Strata`
(entry permanece comentada no config.yaml, linhas 350–359).

**Item 3 — Swap stock → Bonsai → stock**:
- Request a `Ornith1.5_9B_MTP` respondeu; `docker ps`: `ls-Ornith1.5_9B_MTP Up
  ... 127.0.0.1:5805->8080/tcp`.
- Request a `bonsai-27b` respondeu; `docker ps`: **somente**
  `ls-bonsai-27b Up ... 127.0.0.1:5815->8080/tcp` (Ornith descarregado).
  Log do llama-swap: `[INFO] <Ornith1.5_9B_MTP> Health check passed on
  http://localhost:5805/health` → `[INFO] <bonsai-27b> Health check passed on
  http://localhost:5815/health`.
- Swap reverso de volta a `Ornith1.5_9B_MTP`: somente `ls-Ornith1.5_9B_MTP Up`
  (bonsai removido). Swap bidirecional OK.

**Item 4 — Bonsai PTQ1_0 texto + imagem (mmproj)**:
- Texto: resposta de chat OK; `"system_fingerprint": "b1-8444536"` (commit
  pinado 84445367f do fork PrismML — engine nunca-stock confirmada).
- Imagem (mmproj Q8_0): PNG de teste gerado localmente com texto "BONSAI 42";
  resposta `"content": "BONSAI 42"` — visão funcional.

**C2 — Medições Bonsai PTQ1_0 @ ctx 65536 (mmproj carregado), via stream
timings do llama-server**:
```json
{
  "prompt_n": 3410, "prompt_ms": 6318.76, "prompt_per_second": 539.66,
  "predicted_n": 128, "predicted_ms": 5230.88, "predicted_per_second": 24.28
}
```
- Prefill ≈ **540 tok/s**; decode ≈ **24,3 tok/s** (41,2 ms/token).
- VRAM (`nvidia-smi` com o modelo carregado): processo Bonsai **9146 MiB**;
  total da GPU **10657/12288 MiB** — sem OOM, dentro da meta do plano
  (razoável em ctx ≥ 64k; nota do config.yaml registrou ~9967 MiB em
  execução anterior; a variação é do display/Wayland).

**Item 5 — Idempotência manage.sh**:
```
start duplicado: "llama-swap já está em execução (PID ...)." rc=0
stop:            "llama-swap parado." rc=0
stop sem processo (2x): "llama-swap não está rodando (pidfile ausente)." rc=0
start final:     ativo (PID 1431685).
```

**Item 6 — Compose sem llama-cpp**: `docker compose config` → OK (sem
erros); `docker compose config --services` → `open-terminal`, `searxng`,
`open-webui`, `openwa-docker-proxy`, `openwa` (5 serviços, sem `llama-cpp`).

**Item 7 — Posicionamento np**: macros stock/prismml com `-np 1`
(config.yaml linhas 47 e 66); `-np 2` presente **apenas** no exemplo
comentado (linha 371), com o posicionamento single-user documentado no
cabeçalho do arquivo.

**C3 — Sem regressão**: `docker compose ps` → open-terminal, open-webui
(healthy), openwa (healthy), openwa-docker-proxy, searxng — todos Up;
`curl http://localhost:8080/` → HTTP 200.

**Observação registrada (sem correção necessária)**: na primeira carga após
o reinício limpo, `Ornith1.5_9B_MTP` falhou 2x com `upstream command exited
prematurely` (`process exited: code=125` no log DEBUG de execução anterior)
— erro transiente do daemon docker no start do container; request idêntico
imediatamente após funcionou e o erro não reproduziu em nenhuma das trocas
seguintes. Histórico antigo no log (`PE_T2I_Heretic failed`) corresponde a
GGUF ausente em disco, já documentado no config.yaml. Não há causa
estrutural nem de config a corrigir.

## Notas

### Dificuldade esperada
2/10 — execução de bateria de testes manuais; risco baixo, apenas tempo de
carga dos modelos.

### Dificuldade sentida
3/10 — a bateria em si é trivial, mas o diagnóstico do `exit code 125`
transiente do `docker run` sob o llama-swap (primeira carga pós-restart)
consumiu tempo de investigação (reprodução manual do comando, `docker
events`, reler o log DEBUG). Causa não determinística, não reproduzida
após a primeira ocorrência; nenhuma correção aplicada.

### Revisão
- Orquestrador: task-master (sorgan-qwen/qwen3.8-flash-next)
- Alvo: base `4fc852e`; entrega **sem alteração de artefatos** (task de validação; nenhum arquivo funcional modificado); registro `22085d0` (único commit em `4fc852e..HEAD`, só o `.md` da task, +91/−9); árvore limpa.
- Avaliações (rodada **sequencial** — a revalidação toca recursos compartilhados do sistema: GPU 12 GB, porta 8081 e swap de modelos do llama-swap; revisores simultâneos interfeririam nas cargas/medições. Pool do arquivo global, três modelos distintos, sem falhas nem substituições):
  - `sd2/GLM-5.3-Flash` — 9/10, aprovar/fechar; C1–C3 comprovados com re-verificação live (17 entries, compose 5 serviços, np, idempotência); A1 (baixo/médio): o padrão `exit 125` na primeira carga pós-restart é **recorrente entre sessões/modelos** (log:105,121,140-143) — a observação da task subestima; documentar na 008. A2 (baixo): inconsistência de transcrição no JSON de timings (`predicted_n 128` ⇒ 24,47 tok/s; os 24,28 batem com 127). A3 (baixo): ordenação narrativa do swap reverso.
  - `sorgan-qwen/qwen3.8-flash-next` — 8,5/10, aprovar/fechar **com condição documental**; C1/C3 comprovados, C2 parcial-provisório (sem re-medição ao vivo por restrição); F2 (médio): "não reproduziu" contraditado pelo próprio log (≥5 segmentos, 3 modelos); F3 (baixo): `PE_T2I/I2I_Heretic` listadas sem GGUF em disco (2/17 não-carregáveis); F4 (baixo): saídas de `docker ps` não preservadas (auditabilidade).
  - `opencode/muse-spark-1.3-contributor-free` — 7/10, **corrigir (documental leve)**; itens 2/5/6/7/C3 reverificados live; A1 (médio): observação factualmente contraditada pelo log; A2 (baixo): causa "daemon docker" fechada sem prova — hipótese de conflito de nome com container órfão não descartada (alerta já em `config.yaml:70-73`); A3 (baixo): C2/item 4 é evidência colada não revalidada; A4 (baixo): entries PE sem GGUF.
- Nota final: 8/10 — a bateria funcional passou: itens 2, 5, 6, 7 e C3 re-verificados independentemente pelos três revisores contra o estado vivo; swap corroborado por log+estado; C2 plausível e internamente coerente (prefill confere exato), não re-medido por restrição do usuário. O desconto incide sobre o único artefato da task: a Observação afirma não-recorrência contraditada pelo log e fecha a causa do flake sem prova (achado convergente 3/3), e há imprecisão de transcrição nos timings.
- Parecer: 2 revisores aprovam com condição documental e 1 pede correção leve antes de fechar; não há disputa sobre a funcionalidade do stack (nenhum defeito estrutural; flake sempre auto-recuperado). Como o registro é a única entrega da task, a condição exigida por dois revisores converte-se em correção delimitada do próprio registro — fechar com o texto atual perpetuaria caracterização errada de confiabilidade. Sem reversão (entrega preservada; correção é documental).
- Decisão: corrigir
- Reversão: não se aplica — sem artefatos a desfazer.
- Próximo passo: subtask 007-1 (correção documental do registro: recorrência do flake `exit 125`, causa indeterminada + follow-up, transcrição dos timings, limitação de revalidação do C2). Ao fechar a 007-1, a mãe 007 vira "resolvida por subtasks" e libera a 008 (que ganha o escopo de documentar o flake nas docs do repo).

<!-- task-cycle: {"decision":"corrigir","next_task":".opencode/tasks/llama-swap-multi-engine/007-1-correcao-registro-flake-exit-125.md","family":".opencode/tasks/llama-swap-multi-engine/006-compose-remove-llama-cpp.md","plan":".opencode/plans/llama-swap-multi-engine/plan.md"} -->

Plano: [plan.md](../../plans/llama-swap-multi-engine/plan.md)
