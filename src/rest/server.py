import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse

from src.db import count_records, fetch_records
from src.models import BatchResponse, Record

MAX_PAGE_SIZE = 1000
RATE_LIMIT_RPS = 50
_TOKEN_BUCKET_MAX = RATE_LIMIT_RPS
_token_bucket = _TOKEN_BUCKET_MAX
_last_refill: float = 0.0


def _refill_tokens() -> None:
    global _token_bucket, _last_refill
    now = time.monotonic()
    if _last_refill == 0.0:
        _last_refill = now
        return
    elapsed = now - _last_refill
    _token_bucket = min(_TOKEN_BUCKET_MAX, _token_bucket + elapsed * RATE_LIMIT_RPS)
    _last_refill = now


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _last_refill
    _last_refill = time.monotonic()
    yield


app = FastAPI(title="ORTC Pipeline — REST Server", lifespan=lifespan)


@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    global _token_bucket
    _refill_tokens()
    if _token_bucket < 1.0:
        return JSONResponse(
            status_code=429,
            content={"detail": "Rate limit exceeded"},
            headers={"Retry-After": "1"},
        )
    _token_bucket -= 1.0
    return await call_next(request)


@app.get("/records", response_model=BatchResponse)
async def get_records(
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=MAX_PAGE_SIZE, ge=1),
):
    limit = min(limit, MAX_PAGE_SIZE)
    total = count_records()
    if offset >= total:
        return BatchResponse(records=[], total=total, offset=offset, limit=limit)

    rows = fetch_records(offset, limit)
    records = [Record(**{**r, "is_active": bool(r["is_active"])}) for r in rows]
    return BatchResponse(records=records, total=total, offset=offset, limit=limit)


@app.get("/health")
async def health():
    return {"status": "ok", "records": count_records()}


def main():
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)


if __name__ == "__main__":
    main()
