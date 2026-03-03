import asyncio
import json
import time

import httpx
from aiortc import RTCPeerConnection, RTCSessionDescription

from src.models import Record


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

    pc = RTCPeerConnection()
    channel = pc.createDataChannel("records")

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

    offer = await pc.createOffer()
    await pc.setLocalDescription(offer)

    # Exchange signaling via HTTP
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

    answer = RTCSessionDescription(sdp=answer_data["sdp"], type=answer_data["type"])
    await pc.setRemoteDescription(answer)

    # Wait for all records
    try:
        await asyncio.wait_for(done_event.wait(), timeout=300)
    except asyncio.TimeoutError:
        pass

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
