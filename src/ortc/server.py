import asyncio
import json
import logging

from aiohttp import web
from aiortc import RTCConfiguration, RTCIceServer, RTCPeerConnection, RTCSessionDescription

from src.db import count_records, fetch_records
from src.models import Record

logger = logging.getLogger(__name__)

ICE_SERVERS = [RTCIceServer(urls=["stun:stun.l.google.com:19302"])]

pcs: set[RTCPeerConnection] = set()


async def offer_handler(request: web.Request) -> web.Response:
    """Handle signaling: receive an SDP offer, return an SDP answer."""
    body = await request.json()
    batch_size = body.get("batch_size", 100_000)

    offer = RTCSessionDescription(sdp=body["sdp"], type=body["type"])

    config = RTCConfiguration(iceServers=ICE_SERVERS)
    pc = RTCPeerConnection(configuration=config)
    pcs.add(pc)

    @pc.on("connectionstatechange")
    async def on_connectionstatechange():
        logger.info("Connection state: %s", pc.connectionState)
        if pc.connectionState in ("failed", "closed"):
            await pc.close()
            pcs.discard(pc)

    @pc.on("datachannel")
    def on_datachannel(channel):
        logger.info("Data channel established: %s", channel.label)

        @channel.on("open")
        def on_open():
            asyncio.ensure_future(_stream_records(channel, batch_size))

    await pc.setRemoteDescription(offer)
    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)

    return web.json_response({
        "sdp": pc.localDescription.sdp,
        "type": pc.localDescription.type,
    })


async def _stream_records(channel, batch_size: int) -> None:
    """Stream records over the data channel."""
    total = min(batch_size, count_records())
    # Send metadata first
    channel.send(json.dumps({"type": "meta", "total": total}))

    page_size = 1000
    offset = 0
    sent = 0
    while offset < total:
        limit = min(page_size, total - offset)
        rows = fetch_records(offset, limit)
        for r in rows:
            record = Record(**{**r, "is_active": bool(r["is_active"])})
            channel.send(record.serialize())
            sent += 1

        offset += limit
        # Yield to event loop periodically to avoid starving other tasks
        await asyncio.sleep(0)

    channel.send(json.dumps({"type": "done", "sent": sent}))
    logger.info("Streamed %d records", sent)


async def health_handler(request: web.Request) -> web.Response:
    return web.json_response({"status": "ok", "records": count_records()})


async def on_shutdown(app: web.Application) -> None:
    coros = [pc.close() for pc in pcs]
    await asyncio.gather(*coros)
    pcs.clear()


def create_app() -> web.Application:
    app = web.Application()
    app.router.add_post("/offer", offer_handler)
    app.router.add_get("/health", health_handler)
    app.on_shutdown.append(on_shutdown)
    return app


def main():
    logging.basicConfig(level=logging.INFO)
    app = create_app()
    web.run_app(app, host="0.0.0.0", port=8080)


if __name__ == "__main__":
    main()
