# Task 003: Engine Docker dedicada — fork PrismML (llama.cpp-prismml)

Estado: pendente
Depende de: nenhuma
Origem: nenhuma

## Prompt

Criar a imagem Docker dedicada do fork PrismML do llama.cpp, necessária para
servir os GGUFs Bonsai 2 (kernels ternários + Hadamard — **nunca usar imagem
stock**, que recusa `PQ2_0`/`PTQ1_0` ou carrega como `Q2_0` legacy gerando
lixo).

1. Criar `engines/llama.cpp-prismml/Dockerfile`:
   - Base CUDA devel compatível com a toolchain local (o build nativo usa
     nvcc em `/opt/cuda`); alvo **sm_86** (RTX 3060).
   - Clonar `https://github.com/PrismML-Eng/llama.cpp`, branch `prism`,
     **commit pinado `84445367f`** (verificado no checkout local
     `/home/jocic/bonsai-llm/llama.cpp`).
   - Buildar apenas `llama-server` (cmake com CUDA).
2. Criar `engines/llama.cpp-prismml/build.sh`: script que constrói a imagem e
   a tageia como `llama.cpp-prismml:latest` (e `llama.cpp-prismml:84445367f`).
3. Construir a imagem e validar com um container efêmero: rodar `llama-server
   --version` dentro da imagem e conferir que o binário existe.
   (O teste de inferência real com GGUF Bonsai é a task 004, após migração
   dos arquivos.)

Restrições: não baixar modelos; não alterar `config.yaml` (entries Bonsai são
a task 004); commit pinado, nunca `origin/prism` HEAD sem pin.

## Contexto

- `/home/jocic/bonsai-llm/llama.cpp` — checkout local do fork (branch `prism`,
  commit `84445367f`); referência de configuração de build CUDA (nvcc
  `/opt/cuda/bin/nvcc`, arquitetura sm_86). **Não é repo-alvo**; root não é
  git repo.
- `/home/jocic/bonsai-llm/AGENTS.md` — regras duras do fork (nunca stock,
  pins, requisitos de build) — ler antes de escrever o Dockerfile.
- `engines/` — novo diretório no repo.
- https://github.com/PrismML-Eng/llama.cpp (branch `prism`) — fonte do clone.

## Corretude

- [ ] C1 — `./engines/llama.cpp-prismml/build.sh` conclui e
  `docker images` mostra `llama.cpp-prismml:latest` (e tag do commit).
- [ ] C2 — `docker run --rm --gpus all llama.cpp-prismml:latest
  llama-server --version` reporta versão coerente com o commit `84445367f`
  (build CUDA presente).
- [ ] C3 — O Dockerfile pina o commit `84445367f` explicitamente (não HEAD).

## Execução
- Modelo:
- Base:
- Entrega:
- Arquivos da entrega:
- Evidências:

## Notas

### Dificuldade esperada
5/10 — build de llama.cpp com CUDA em container (tempo de compilação longo,
choices de base image/toolchain); lógica simples, risco em detalhes de toolchain.

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
