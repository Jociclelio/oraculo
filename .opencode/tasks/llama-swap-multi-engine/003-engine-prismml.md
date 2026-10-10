# Task 003: Engine Docker dedicada — fork PrismML (llama.cpp-prismml)

Estado: aguardando revisão
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

- [x] C1 — `./engines/llama.cpp-prismml/build.sh` conclui e
  `docker images` mostra `llama.cpp-prismml:latest` (e tag do commit).
- [x] C2 — `docker run --rm --gpus all llama.cpp-prismml:latest
  llama-server --version` reporta versão coerente com o commit `84445367f`
  (build CUDA presente).
- [x] C3 — O Dockerfile pina o commit `84445367f` explicitamente (não HEAD).

## Execução
- Modelo: GLM-5.3-Flash (`sd2/GLM-5.3-Flash`), via agente task-executor (OpenCode)
- Base: `a54b707` (árvore limpa, branch `main`)
- Entrega: `1b3b346` — feat: engine Docker PrismML do llama.cpp (commit pinado 84445367f, sm_86) para GGUFs Bonsai 2
- Arquivos da entrega:
  - `engines/llama.cpp-prismml/Dockerfile`
  - `engines/llama.cpp-prismml/build.sh`
- Evidências:
  - C1 — `./engines/llama.cpp-prismml/build.sh` concluiu com exit 0 (log completo
    em `/tmp/opencode/build-prismml.log`); `docker images` mostra
    `llama.cpp-prismml:latest` e `llama.cpp-prismml:84445367f` (14,4 GB, ID
    `d88136167019`, ambas apontando para a mesma imagem).
  - C2 — `docker run --rm --gpus all llama.cpp-prismml:latest llama-server --version`
    → `version: 0.2.0-dev (build 1, commit 8444536)` / `built with GNU 13.3.0 for
    Linux x86_64` — coerente com o commit pinado `84445367f`. Build CUDA presente:
    `cuobjdump --list-elf` no binário dentro da imagem contabiliza **146 ELF
    `sm_86`** (alvo RTX 3060) e `GGML_CUDA_REGISTER_HOST` presente.
  - C3 — Dockerfile usa `ARG PRISMML_COMMIT="84445367fbaf79c00ff64bc93a0689cdb3eee54d"`
    (sha completo) com `git checkout --detach` + `test "$(git rev-parse HEAD)" =`
    (build falha se o pin não bater); dentro da imagem, `git -C /src rev-parse HEAD`
    = `84445367fbaf79c00ff64bc93a0689cdb3eee54d`, checkout local de referência
    `/home/jocic/bonsai-llm/llama.cpp` (branch `prism`) no mesmo SHA — conferido.
  - Binário existe: `test -x /usr/local/bin/llama-server` → OK dentro da imagem.
- Notas de implementação:
  - Base `nvidia/cuda:13.4.2-devel-ubuntu24.04` — alinhada ao nvcc 13.4 do build
    nativo de referência (`/opt/cuda`), driver host 615.71, sm_86 suportado.
  - `BUILD_SHARED_LIBS=OFF` (ggml estático no binário) evita RUNPATH dependente
    do diretório de build; sem ENTRYPOINT/CMD, `docker run <img> llama-server ...`
    resolve direto (formato exigido pelo llama-swap).
  - Build não requer GPU (arquitetura fixa via `CMAKE_CUDA_ARCHITECTURES=86`).
  - `build.sh` inclui sanity check sem `--gpus` (`--version` não inicializa CUDA).
  - Fonte do fork mantida em `/src` dentro da imagem (proveniência/pin auditável).
  - Imagem pré-existente não relacionada no host (`llama-cpp-bonsai:latest`, 2 meses,
    base CUDA 12.1 via cópia de build local) foi identificada e ignorada — não é
    reproduzível nem pinada; a nova imagem é autônoma.

## Notas

### Dificuldade esperada
5/10 — build de llama.cpp com CUDA em container (tempo de compilação longo,
choices de base image/toolchain); lógica simples, risco em detalhes de toolchain.

### Dificuldade sentida
4/10 — fluxo direto e bem guidado pela task (pin, flags e referência local já
definidos); a única incerteza real era a escolha da tag base CUDA (resolvida
alinhando ao nvcc 13.4 do host) e o RUNPATH dos libs do ggml (resolvido com
`BUILD_SHARED_LIBS=OFF`). Build CUDA levou os minutos esperados, sem surpresas.

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
