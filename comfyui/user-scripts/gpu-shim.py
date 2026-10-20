#!/usr/bin/env python3
"""gpu-shim — proxy reverso do ComfyUI com liberação de VRAM sob demanda.

A 3060 de 12 GB é compartilhada entre o ComfyUI (difusão) e o llama-swap
(LLM). O ComfyUI já libera a VRAM ao fim de cada geração
(--disable-smart-memory), mas no sentido inverso o modelo de difusão
(~8-9 GB no pico) não carrega se um LLM estiver residente.

Este shim ocupa a porta canônica 8188 (o ComfyUI fica em 127.0.0.1:8189) e
repassa HTTP e WebSocket para o ComfyUI. Antes de repassar TRÁFEGO DE
GERAÇÃO ele avalia a VRAM livre (nvidia-smi) e, se insuficiente (< 8 GiB),
pede ao llama-swap GET /unload — síncrono (~0,5 s) — e aguarda a VRAM
aparecer. Regras para não virar um job autônomo:

- Tráfego da UI NATIVA (Origin :8188 — o frontend faz polling contínuo)
  NUNCA dispara unload; só o caminho de geração (Open WebUI/API, sem Origin
  de UI) pode.
- Mesmo no caminho de geração, o unload só ocorre se a VRAM realmente não
  bastar — sem modelo carregado, nenhum efeito colateral.
- Sem job em background: quando o LLM for necessário de novo, o llama-swap
  o recarrega sozinho no próximo request.

Escrito contra aiohttp (dependência nativa da imagem comfyui-boot).
"""
import asyncio
import logging
import subprocess
import time

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web

UPSTREAM = "http://127.0.0.1:8189"
LLAMA_SWAP_UNLOAD = "http://127.0.0.1:8081/unload"
LISTEN_HOST, LISTEN_PORT = "127.0.0.1", 8188
UI_ORIGIN_PORT = "8188"          # Origin da UI nativa do ComfyUI
FREE_THRESHOLD_MIB = 8192        # pico do DiT + VAE coube em ~8,3 GiB livres
CHECK_INTERVAL_S = 2.0           # cache da leitura de VRAM
WAIT_AFTER_UNLOAD_S = 45         # teto de espera pela VRAM pós-unload
STABLE_POLLS = 6                 # leituras estáveis (0,5 s) encerram a espera

HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "host",
    "content-encoding", "content-length",
}

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("gpu-shim")

session: ClientSession | None = None
unload_lock = asyncio.Lock()
_vram_cache = (0.0, None)  # (timestamp, free_mib)


def gpu_free_mib():
    """VRAM livre (MiB) via nvidia-smi; None se indisponível."""
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=memory.total,memory.used",
             "--format=csv,noheader,nounits"], text=True)
        total, used = (int(x) for x in out.strip().splitlines()[0].split(","))
        return total - used
    except Exception as e:
        log.warning("nvidia-smi falhou (%s); não vou descarregar nada", e)
        return None


def cached_free_mib():
    global _vram_cache
    ts, val = _vram_cache
    now = time.monotonic()
    if val is None or now - ts > CHECK_INTERVAL_S:
        val = gpu_free_mib()
        _vram_cache = (now, val)
    return val


def is_generation_traffic(request: web.Request) -> bool:
    """True se o request vem do caminho de geração (Open WebUI/API).

    O frontend da UI nativa manda Origin: http://<host>:8188 em tudo
    (inclusive o polling /api/jobs) — esse tráfego nunca descarrega. O
    backend do Open WebUI (aiohttp) não manda Origin.
    """
    origin = request.headers.get("Origin", "")
    return not (origin and origin.rsplit(":", 1)[-1] == UI_ORIGIN_PORT)


async def ensure_vram(request: web.Request):
    if not is_generation_traffic(request):
        return
    free = cached_free_mib()
    if free is None or free >= FREE_THRESHOLD_MIB:
        return
    async with unload_lock:
        free = gpu_free_mib()
        if free is None or free >= FREE_THRESHOLD_MIB:
            return
        # flusha o caching allocator do PyTorch do ComfyUI (POST /free) —
        # devolve blocos CUDA retidos em idle/fragmentação para o driver.
        # O piso do runtime (~200-300 MiB de contexto CUDA + cuBLAS/cuDNN)
        # não é liberável sem matar o processo (custo: restart do torch).
        try:
            async with session.post(UPSTREAM + "/free", json={
                    "unload_models": True, "free_memory": True}) as r:
                log.info("VRAM livre %s MiB < %s; flush do ComfyUI /free: %s",
                         free, FREE_THRESHOLD_MIB, r.status)
        except Exception as e:
            log.warning("/free indisponível (%s); seguindo", e)
        try:
            async with session.get(LLAMA_SWAP_UNLOAD, timeout=ClientTimeout(total=60)) as r:
                log.info("VRAM livre %s MiB < %s; unload llama-swap: %s %s",
                         free, FREE_THRESHOLD_MIB, r.status, await r.text())
        except Exception as e:
            log.warning("unload indisponível (%s); seguindo", e)
            return
        deadline = time.monotonic() + WAIT_AFTER_UNLOAD_S
        last, stable = None, 0
        while time.monotonic() < deadline:
            await asyncio.sleep(0.5)
            free = gpu_free_mib()
            if free is None:
                continue
            if free >= FREE_THRESHOLD_MIB:
                log.info("VRAM liberada: %s MiB livres", free)
                return
            # teardown do processo de LLM pode levar dezenas de segundos;
            # se a leitura estabilizou, não vale a pena esperar mais
            if free == last:
                stable += 1
                if stable >= STABLE_POLLS:
                    log.info("VRAM estável em %s MiB livres; seguindo", free)
                    return
            else:
                stable = 0
            last = free
        log.warning("VRAM ainda apertada após unload (%s MiB livres); seguindo "
                    "(jogo/desktop podem estar ocupando)", free)


def clean_headers(headers):
    return {k: v for k, v in headers.items() if k.lower() not in HOP_BY_HOP}


def upstream_url(request: web.Request) -> str:
    """Caminho cru (percent-preserved).

    rel_url.path decodifica %2F — e no backend do ComfyUI a codificação é
    semântica: /api/userdata/workflows%2Ffoo.json casa com /userdata/{file}
    e o handler decodifica; com a barra real a rota de segmento único não
    casa e dá 404 (quebrou o override de templates na UI nativa).
    """
    return f"{UPSTREAM}{request.raw_path}"


async def proxy_http(request: web.Request):
    await ensure_vram(request)
    body = await request.read()
    async with session.request(
        request.method,
        upstream_url(request),
        data=body,
        headers=clean_headers(request.headers),
    ) as resp:
        payload = await resp.read()
        return web.Response(status=resp.status, body=payload,
                            headers=clean_headers(resp.headers))


async def proxy_ws(request: web.Request):
    await ensure_vram(request)
    ws_server = web.WebSocketResponse()
    await ws_server.prepare(request)
    async with session.ws_connect(upstream_url(request)) as ws_client:
        async def to_client():
            async for msg in ws_server:
                if msg.type == WSMsgType.TEXT:
                    await ws_client.send_str(msg.data)
                elif msg.type == WSMsgType.BINARY:
                    await ws_client.send_bytes(msg.data)
                else:
                    break

        async def to_shim():
            async for msg in ws_client:
                if msg.type == WSMsgType.TEXT:
                    await ws_server.send_str(msg.data)
                elif msg.type == WSMsgType.BINARY:
                    await ws_server.send_bytes(msg.data)
                else:
                    break

        await asyncio.gather(to_client(), to_shim())
    return ws_server


async def dispatch(request: web.Request):
    if request.headers.get("Upgrade", "").lower() == "websocket":
        return await proxy_ws(request)
    return await proxy_http(request)


async def main():
    global session
    session = ClientSession()
    app = web.Application(client_max_size=1024**3)
    app.router.add_route("*", "/{path:.*}", dispatch)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, LISTEN_HOST, LISTEN_PORT)
    log.info("gpu-shim em http://%s:%s -> %s (unload sob demanda: %s)",
             LISTEN_HOST, LISTEN_PORT, UPSTREAM, LLAMA_SWAP_UNLOAD)
    await site.start()
    while True:
        await asyncio.sleep(3600)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
