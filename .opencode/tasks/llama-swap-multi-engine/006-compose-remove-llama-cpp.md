# Task 006: docker-compose.yml — remover serviço llama-cpp

Estado: aguardando revisão
Depende de: 004
Origem: nenhuma

## Prompt

Remover do `docker-compose.yml` o serviço `llama-cpp`, cujo papel foi
assumido pelo llama-swap no host (porta 8081 preservada):

1. Remover o serviço `llama-cpp` inteiro (imagem, container, GPU, volumes).
2. Remover o mount do `models.ini` que existia apenas para esse serviço
   (`./models.ini → /app/models.ini`). Os demais mounts/volumes (open-webui,
   open-terminal, searxng, openwa, openwa-docker-proxy) permanecem **intocados**.
3. Confirmar que nenhum outro serviço referencia o container `llama-cpp` ou a
   rede/volume dele (a WebUI aponta para `localhost:8081`, que agora é o
   llama-swap do host — nada a mudar no env).
4. Validar: `docker compose config` sem erros; `docker compose ps` não mostra
   `llama-cpp`; o serving continua de pé via llama-swap (`curl
   http://localhost:8081/v1/models`).

Restrições: não remover ainda o arquivo `models/models.ini` do repo (fonte
histórica dos parâmetros; desativação física/documental é tratada na task
008); não mexer nos demais serviços.

## Contexto

- `docker-compose.yml` — alvo da edição; seção `llama-cpp` a remover.
- `DOCKER.md` — documentará a mudança (task 008; só conferir aqui que o
  compose atual ainda corresponde ao doc até a task 008 rodar).
- `manage.sh` — já reescrito (task 001), não usa mais `docker compose` para o
  serving.

## Corretude

- [ ] C1 — `docker compose config` válida (exit 0) sem o serviço `llama-cpp`.
- [ ] C2 — `grep -i llama-cpp docker-compose.yml` sem resultados e sem
  referência ao mount `models.ini`.
- [ ] C3 — `docker compose ps` lista apenas open-webui, open-terminal,
  searxng, openwa e openwa-docker-proxy.
- [ ] C4 — `curl http://localhost:8081/v1/models` responde (llama-swap
  assumiu a porta).

## Execução
- Modelo: sd2/GLM-5.3-Flash
- Base: 7805f7d (árvore limpa)
- Entrega: 05ab52d394f9251ffa173d6f4514922605303268
- Arquivos da entrega: `docker-compose.yml`
- Evidências:
  - C1 ✅ — `docker compose config` exit 0 (sem o serviço `llama-cpp`).
  - C2 ✅ — `grep -in "llama-cpp\|models.ini" docker-compose.yml` sem
    resultados (exit 1); mount `./models/models.ini:/app/models.ini` removido
    junto com o serviço.
  - C3 ✅ — `docker compose ps` lista apenas open-webui, open-terminal,
    searxng, openwa e openwa-docker-proxy (sem `llama-cpp`).
  - C4 ✅ — `curl http://localhost:8081/v1/models` exit 0, resposta JSON do
    llama-swap (`owned_by: "llama-swap"`) com os modelos stock + Bonsai
    (todos `unloaded`).
- Observações:
  - Removido também o `depends_on: - llama-cpp` do `open-webui`
    (referência residual; `searxng` mantido).
  - Demais serviços intocados; `models/models.ini` preservado no repo
    (tratado na task 008); DOCKER.md não editado (task 008).

## Notas

### Dificuldade esperada
1/10 — remoção de bloco YAML e validação de compose; trivial.

### Dificuldade sentida
1/10 — remoção de bloco YAML + `depends_on` e validação com os comandos
previstos; nenhum impedimento encontrado.

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
