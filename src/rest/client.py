import asyncio
import time

import httpx

from src.models import Record


async def fetch_all_records(
    base_url: str,
    batch_size: int,
    page_size: int = 1000,
) -> tuple[list[Record], dict]:
    """Fetch batch_size records from the REST server, page by page.

    Returns (records, metrics) where metrics contains timing information.
    """
    records: list[Record] = []
    t_start = time.perf_counter()
    t_first_record: float | None = None

    async with httpx.AsyncClient(base_url=base_url, timeout=60.0) as client:
        offset = 0
        while offset < batch_size:
            limit = min(page_size, batch_size - offset)
            try:
                resp = await client.get("/records", params={"offset": offset, "limit": limit})
            except httpx.HTTPError as exc:
                raise RuntimeError(f"HTTP request failed: {exc}") from exc

            if resp.status_code == 429:
                retry_after = float(resp.headers.get("Retry-After", "1"))
                await asyncio.sleep(retry_after)
                continue

            resp.raise_for_status()
            data = resp.json()

            page_records = [Record(**r) for r in data["records"]]
            if not page_records:
                break

            if t_first_record is None and page_records:
                t_first_record = time.perf_counter()

            records.extend(page_records)
            offset += len(page_records)

            if offset >= data["total"]:
                break

    t_end = time.perf_counter()
    total_time = t_end - t_start
    ttfr = (t_first_record - t_start) if t_first_record else total_time

    metrics = {
        "mode": "rest",
        "batch_size": batch_size,
        "records_received": len(records),
        "time_to_first_record_s": round(ttfr, 6),
        "total_transfer_time_s": round(total_time, 6),
        "records_per_sec": round(len(records) / total_time, 2) if total_time > 0 else 0,
    }
    return records, metrics
