# Strata (Qwen3.8-Flash-Next) — infra preparada, instalação futura

Infraestrutura do **Strata** (engine oficial para o Qwen3.8-Flash-Next,
https://github.com/Niko1221/Strata) preparada no repo **sem baixar o modelo**
(~58 GB na variante Coder — fora de escopo, decisão do plano llama-swap
multi-engine).

- `Dockerfile` — adaptado do Dockerfile oficial do upstream, com o código
  clonado em commit pinado (`61b3fb5dd3f1e8ec09cf7e4e05208bc6d3c46406`) e as
  env `MODEL` / `FAMILY` / `CONTEXT` preservadas (defaults fixados na variante
  Coder, ver abaixo). O build **compila a engine, não baixa pesos** — o
  download do modelo acontece só no primeiro start do container.
- `build-engine.py` — script de compilação da engine, extraído do heredoc do
  Dockerfile upstream (o builder Docker desta máquina, sem buildx, não suporta
  heredoc: com heredoc o RUN "passa" sem executar e a imagem sai sem engine).
- `llama-swap/config.yaml` — entry do Strata **desabilitada (comentada)**, com
  `MODEL=IQ1_M`, `FAMILY=coder` e `CONTEXT=65536`.

## Requisitos (nesta máquina)

| Requisito | Valor | Situação |
|-----------|-------|----------|
| GPU | NVIDIA 12 GB+ (driver >= 580, nvidia-container-toolkit) | RTX 3060 12 GB — OK |
| **RAM** | **31 GB** para a variante **Coder** (a máquina tem 32 GB; é a única variante que cabe — Q2_0/IQ2_XS exigem 37,6/39,2 GB de RAM+VRAM segundo o upstream, ou modo low-RAM com GPU de 24 GB; as demais não cabem) | 31 GiB — OK |
| Disco | ~58 GB para o modelo (Coder IQ1_M; ~65 GB com a camada MTP) + pack preparado | em `/home` (NVMe XPG Gammix S70, ~320 GB livres) |
| Engine | compilada no `docker build` (CPU nativa + CUDA sm_86) | feita no build da imagem |

> A variante **Coder** mantém 91% do SWE-bench Verified do modelo cheio, mas é
> mais fraca fora de código (incl. texto CJK). Para uso geral, as alternativas
> (Q2_0, mais rápida; IQ2_XS, melhor qualidade) **não cabem** nos 32 GB desta
> máquina: o upstream exige 37,6 GB (Q2_0) / 39,2 GB (IQ2_XS) de RAM+VRAM — em
> PC de 32 GB só rodam em modo low-RAM com GPU de 24 GB (não é o caso: RTX 3060
> 12 GB). Trocar com `docker run -e MODEL=... -e FAMILY=...` (e `REINSTALL=1`
> para trocar configurações de um modelo já instalado).

## Passos de instalação futura (quando autorizado)

O modelo deve ficar em **`/home` (NVMe)**, nunca no SSD SATA nem no HDD: o
primeiro start lê/escreve ~58 GB e o pack de experts é acessado durante a
inferência.

```bash
# 1. Build da imagem (compila a engine; NÃO baixa o modelo):
docker build -t strata ./strata

# 2. Diretório de dados do modelo no NVMe:
mkdir -p /home/jocic/strata-data

# 3. Primeiro start — baixa o modelo (~58 GB na variante Coder IQ1_M,
#    retomável se interrompido), prepara o pack e sobe a API em
#    http://127.0.0.1:8080/v1:
docker run --rm --gpus all \
  -p 127.0.0.1:8080:8080 \
  --ulimit memlock=-1 \
  -v /home/jocic/strata-data:/data \
  -e MODEL=IQ1_M -e FAMILY=coder -e CONTEXT=65536 \
  strata

#    (as -e são redundantes com os defaults do Dockerfile; explícitas por
#    clareza. Durante a carga o PC pode ficar lento por 1-3 min — normal:
#    ~30 GB vão para a RAM — o shard 1 do Coder tem 29,6 GB.)
```

## Entry de ativação no llama-swap

Com o modelo instalado e testado (passo acima), descomentar no
`llama-swap/config.yaml` o bloco `Strata:` (já pronto, com `MODEL=IQ1_M`,
`FAMILY=coder`, `CONTEXT=65536` e o mount `/home/jocic/strata-data:/data`) e
reiniciar o proxy:

```bash
./manage.sh stop && ./manage.sh start
curl http://localhost:8081/v1/models   # Strata deve aparecer
```

O llama-swap faz o swap automático: ao pedir o modelo `Strata`, o modelo
anterior é descarregado (`docker rm -f`) e o container do Strata sobe.

## Notas operacionais

- **Porta**: o Strata serve em `:8080` interno (padrão upstream); a entry do
  llama-swap publica em `127.0.0.1:${PORT}` só no loopback, como as demais.
- **Uma request por vez** (default upstream); `"parallel": 2` degrada em 12 GB.
- **API key**: só necessária se expor a porta à rede (`-e API_KEY=<secret>`).
- **Trocar settings** de um modelo já instalado (ctx, visão, KV): reiniciar com
  `-e REINSTALL=1`.
- Referência upstream: `docs/INSTALL.md`, `docs/MODELS.md`,
  `docs/TROUBLESHOOTING.md` no repositório Niko1221/Strata.
