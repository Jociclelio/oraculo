# Task 001: Instalar llama-swap (host) e reescrever manage.sh

Estado: pendente
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

- [ ] C1 — `./llama-swap/install.sh` baixa binário executável em `bin/` e
  `bin/llama-swap --help` (ou versão) responde sem erro.
- [ ] C2 — `./manage.sh start` inicia o processo em background, cria
  `logs/llama-swap.pid` e `logs/llama-swap.log`; `kill -0 $(cat
  logs/llama-swap.pid)` confirma processo vivo.
- [ ] C3 — `./manage.sh stop` encerra o processo registrado no pidfile e remove
  o pidfile; rodar `stop` duas vezes seguidas não falha.
- [ ] C4 — `git status` não mostra `bin/` nem `logs/` como não rastreados.

## Execução
- Modelo:
- Base:
- Entrega:
- Arquivos da entrega:
- Evidências:

## Notas

### Dificuldade esperada
3/10 — script de instalação e rewrite de shell script conhecido; incerteza
apenas nos flags exatos do binário do llama-swap.

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
