import asyncio
import json
import logging
import time

import httpx
from aiortc import RTCConfiguration, RTCIceServer, RTCPeerConnection, RTCSessionDescription

from src.models import Record

logger = logging.getLogger(__name__)

ICE_SERVERS = [RTCIceServer(urls=["stun:stun.l.google.com:19302"])]


async def fetch_all_records(
    signaling_url: str,
    batch_size: int,
) -> tuple[list[Record], dict]:
    """Connect to the ORTC server via signaling and receive records over a data channel.

    Returns (records, metrics) where metrics contains timing information.
    """
    records: list[Record] = []
    t_start = time.perf_counter()
    t_first_record: float | None = None
    done_event = asyncio.Event()
    failed_event = asyncio.Event()

    config = RTCConfiguration(iceServers=ICE_SERVERS)
    pc = RTCPeerConnection(configuration=config)
    channel = pc.createDataChannel("records")

    @pc.on("connectionstatechange")
    async def on_connectionstatechange():
        logger.info("Connection state: %s", pc.connectionState)
        if pc.connectionState == "failed":
            logger.error("ICE connection failed")
            failed_event.set()
        elif pc.connectionState == "connected":
            logger.info("ICE connection established")

    @pc.on("iceconnectionstatechange")
    async def on_iceconnectionstatechange():
        logger.info("ICE connection state: %s", pc.iceConnectionState)

    @pc.on("icegatheringstatechange")
    async def on_icegatheringstatechange():
        logger.info("ICE gathering state: %s", pc.iceGatheringState)

    @channel.on("open")
    def on_open():
        logger.info("Data channel opened")

    @channel.on("message")
    def on_message(message):
        nonlocal t_first_record

        data = message if isinstance(message, str) else message.decode()

        # Check for control messages
        if data.startswith('{"type":'):
            ctrl = json.loads(data)
            if ctrl.get("type") == "meta":
                return
            if ctrl.get("type") == "done":
                done_event.set()
                return

        if t_first_record is None:
            t_first_record = time.perf_counter()

        record = Record.deserialize(data)
        records.append(record)

    logger.info("Creating offer...")
    offer = await pc.createOffer()
    await pc.setLocalDescription(offer)

    # Exchange signaling via HTTP
    logger.info("Sending offer to %s/offer", signaling_url)
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{signaling_url}/offer",
            json={
                "sdp": pc.localDescription.sdp,
                "type": pc.localDescription.type,
                "batch_size": batch_size,
            },
        )
        resp.raise_for_status()
        answer_data = resp.json()

    logger.info("Received answer, setting remote description")
    answer = RTCSessionDescription(sdp=answer_data["sdp"], type=answer_data["type"])
    await pc.setRemoteDescription(answer)

    # Wait for records or connection failure
    done_or_failed = asyncio.ensure_future(
        asyncio.wait(
            [
                asyncio.ensure_future(done_event.wait()),
                asyncio.ensure_future(failed_event.wait()),
            ],
            return_when=asyncio.FIRST_COMPLETED,
        )
    )
    try:
        await asyncio.wait_for(done_or_failed, timeout=120)
    except asyncio.TimeoutError:
        logger.error("Timed out waiting for records (120s)")

    if failed_event.is_set():
        raise ConnectionError(
            f"WebRTC connection failed (state={pc.connectionState}, "
            f"ice={pc.iceConnectionState})"
        )

    t_end = time.perf_counter()
    await pc.close()

    total_time = t_end - t_start
    ttfr = (t_first_record - t_start) if t_first_record else total_time

    metrics = {
        "mode": "ortc",
        "batch_size": batch_size,
        "records_received": len(records),
        "time_to_first_record_s": round(ttfr, 6),
        "total_transfer_time_s": round(total_time, 6),
        "records_per_sec": round(len(records) / total_time, 2) if total_time > 0 else 0,
    }
    return records, metrics
