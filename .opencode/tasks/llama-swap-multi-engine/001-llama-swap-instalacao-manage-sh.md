# Task 001: Instalar llama-swap (host) e reescrever manage.sh

Estado: fechada
Depende de: nenhuma
Origem: nenhuma

## Prompt

Instalar o binário de release do llama-swap no host e reescrever o `manage.sh`
para gerenciá-lo, substituindo o ciclo docker compose do `llama-cpp`.

1. Criar `llama-swap/install.sh`: script que baixa o binário de release mais
   recente de https://github.com/mostlygeek/llama-swap/releases para `bin/`
   (criar o diretório se necessário), tornando-o executável. Detectar
   arquitetura (x86_64) e falhar com mensagem clara se o download falhar.
2. Reescrever `manage.sh`:
   - `start`: se já houver processo do llama-swap ativo (via pidfile), avisar e
     sair; caso contrário, iniciar `bin/llama-swap -config llama-swap/config.yaml`
     em background, gravando PID em `logs/llama-swap.pid` e saída em
     `logs/llama-swap.log`. Aguardar a porta `8081` responder (curl em
     `/v1/models`) antes de reportar sucesso.
   - `stop`: ler o pidfile, encerrar o processo (SIGTERM, com fallback SIGKILL
     após timeout), remover pidfile.
   - `status`: opcional, mostra se está rodando.
   - A config ainda não existirá nesta task; o script deve reportar erro
     legível se `-config` apontar para arquivo inexistente (não é preciso
     stubar config só para esta task).
3. Adicionar `bin/` e `logs/` ao `.gitignore`.

Restrições: não criar ainda o `config.yaml` definitivo (é a task 002); não
alterar docker-compose.yml nem outros serviços.

## Contexto

- `manage.sh` — script atual que sobe container docker `llama-cpp`; será
  reescrito por inteiro.
- `.gitignore` — adicionar entradas de artefatos locais.
- `docker-compose.yml` — referência da porta 8081 que deve permanecer inalterada
  (WebUI já usa `OAI_API_BASE=http://localhost:8081/v1` no `webui.db`).
- https://github.com/mostlygeek/llama-swap — conferir nome/nomeação dos assets
  de release e flags do binário (`-config`, porta via config).

## Corretude

- [x] C1 — `./llama-swap/install.sh` baixa binário executável em `bin/` e
  `bin/llama-swap --help` (ou versão) responde sem erro.
- [x] C2 — `./manage.sh start` inicia o processo em background, cria
  `logs/llama-swap.pid` e `logs/llama-swap.log`; `kill -0 $(cat
  logs/llama-swap.pid)` confirma processo vivo.
- [x] C3 — `./manage.sh stop` encerra o processo registrado no pidfile e remove
  o pidfile; rodar `stop` duas vezes seguidas não falha.
- [x] C4 — `git status` não mostra `bin/` nem `logs/` como não rastreados.

## Execução
- Modelo: GLM-5.3-Flash (ID real do runtime: `sd2/GLM-5.3-Flash`)
- Base: eb41d0d
- Entrega: 748f589a34192da04c951fe36f7f5a13cc47855f
- Arquivos da entrega: `llama-swap/install.sh` (novo), `manage.sh` (reescrito), `.gitignore` (+`bin/`, `logs/`)
- Evidências:
  - C1 — `./llama-swap/install.sh` baixou release v263
    (`llama-swap_263_linux_amd64.tar.gz`) para `bin/llama-swap` (executável);
    `--help` lista `-config`, `-listen` etc.; `--version` → `v263 (e33e97b)`.
  - C2/C3 — validados com config temporário `models: {}` (criado apenas para o
    teste e removido depois; não commitado): `start` subiu em background,
    log confirma `listening on http://127.0.0.1:8081`, `/v1/models` respondeu,
    `kill -0` confirmou o PID vivo; `start` duplicado avisou e saiu; `status`
    ok; `stop` encerrou via SIGTERM, removeu pidfile; segundo `stop` saiu com
    sucesso (idempotente).
  - C4 — `git status --porcelain` não lista `bin/` nem `logs/`.
  - Descobertas: (a) o endereço de escuta NÃO vai no `config.yaml` — o env
    `LLAMA_SWAP_LISTEN` não é honrado na v263; fixado via flag `-listen
    127.0.0.1:8081` no `manage.sh` (desvio mínimo e documentado do comando
    literal da task, necessário para a porta 8081); (b) o `manage.sh` confirma
    sucesso apenas com o PID próprio vivo — evita falso positivo quando outra
    coisa ocupa a 8081 (ocorreu no teste com o container `llama-cpp` antigo).
  - Estado do host: o container `llama-cpp` antigo foi parado (`docker stop`)
    durante a validação para liberar a porta 8081 e foi deixado parado — é o
    serviço que o plano substitui (remoção do compose é a task 006). Sem
    alteração no `docker-compose.yml` nem nos demais serviços.

## Notas

### Dificuldade esperada
3/10 — script de instalação e rewrite de shell script conhecido; incerteza
apenas nos flags exatos do binário do llama-swap.

### Dificuldade sentida
3/10 — implementação direta; o único ponto de atrito real foi a porta de
escuta (env `LLAMA_SWAP_LISTEN` documentado não funciona na v263, exigindo a
flag `-listen`), e o container antigo `llama-cpp` ocupava a 8081 durante o
teste, mascarando o resultado até ser parado.

### Revisão
- Orquestrador: GLM-5.3-Flash (`sd2/GLM-5.3-Flash`)
- Alvo: task 001; base `eb41d0d`; entrega `748f589`; registro `a5534e2`.
  Modo da rodada: **sequencial** — a validação executa `manage.sh`/`llama-swap`
  (porta 8081, pidfiles, processo em background), recursos compartilhados que
  se interfeririam em paralelo. Pool lido de `.opencode/task-reviewer-pool.md`;
  os três primeiros disponíveis formaram o quórum. Nenhum revisor falhou.
- Avaliações:
  1. GLM-5.3-Flash (`sd2/GLM-5.3-Flash`) — **9,5/10, aprovado**. Confirmou
     C1–C4 por execução própria (start/stop/status, start duplicado, erro
     legível sem config, check-ignore). Achados menores: A1 `is_running()`
     sem validar nome do processo (PID reciclado); A2 `grep -oP` não
     portável; A3 SIGKILL sem relato final. Nenhum crítico/maior.
  2. qwen3.8-flash-next (`sorgan-qwen/qwen3.8-flash-next`) — **9/10,
     aprovado**. Confirmou C1–C4 por execução própria e validou o padrão do
     asset contra a API de releases ao vivo (v263). Achados menores: A1
     timeout de 30 s deixa processo+pidfile sem orientação de `stop`; A2
     `--version` pós-install engole falha (`|| true`); A3 alegação do env
     `LLAMA_SWAP_LISTEN` não honrado não re-verificada (irrelevante à
     corretude).
  3. muse-spark-1.3 (`opencode/muse-spark-1.3-contributor-free`) — **9/10,
     aprovado**. Confirmou C1–C4 por execução própria. Achados menores: P1
     `grep -oP` (portabilidade, com fallback correto); P2 mesmo A1 do
     revisor 2 (timeout deixa processo/pidfile); P3 sem checksum do asset.
- Nota final: **9,5/10** — os três revisores aprovaram com execução
  independente dos quatro critérios; convergência total na corretude e no
  escopo (compose intocado, config.yaml ausente conforme planejado). Os
  desvios do literal da task (`-listen 127.0.0.1:8081`, guarda de PID próprio)
  foram considerados pelos três melhorias necessárias e documentadas. Nota
  final acima da média simples reflete a ausência de qualquer achado
  crítico/maior e a robustez acima do mínimo exigido (pidfile órfão, guarda
  `comm` antes do kill, idempotência do stop). Os achados menores (A1 do
  timeout sem orientação de `stop`, portabilidade de `grep -oP`) ficam como
  dívida técnica opcional — podem ser absorvidos gratuitamente na task 002,
  sem subtask de correção.
- Parecer: entrega fiel ao escopo, íntegra e validada por três modelos
  distintos. Higiene do host confirmada pelos revisores (sem processo
  residual, sem config temporário, `git status` limpo).
- Decisão: **fechar** — todos os critérios obrigatórios comprovados; libera
  a task 002.
- Reversão: não se aplica — sem artefatos a reverter (aprovada).
- Próximo passo: executar task 002
  (`.opencode/tasks/llama-swap-multi-engine/002-config-yaml-stock.md`),
  dependente desta. Observações úteis para a 002: a porta de escuta é fixada
  via flag `-listen` (não via config/env); o llama-swap v263 tem autodiscovery
  de `models.ini` (modelos apareceram com `"source":"preset"` durante os
  testes) — conferir se isso interfere na configuração explícita desejada.

<!-- task-cycle: {"decision":"fechar","next_task":".opencode/tasks/llama-swap-multi-engine/002-config-yaml-stock.md","family":".opencode/tasks/llama-swap-multi-engine/001-llama-swap-instalacao-manage-sh.md","plan":".opencode/plans/llama-swap-multi-engine/plan.md"} -->

Plano: [plan.md](../../plans/llama-swap-multi-engine/plan.md)
