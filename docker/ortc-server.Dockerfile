FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libavcodec-dev libavformat-dev libavutil-dev \
        libopus-dev libvpx-dev pkg-config gcc && \
    rm -rf /var/lib/apt/lists/*

ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY src/ src/
COPY data/records.db data/records.db

RUN uv sync --frozen --no-dev

EXPOSE 8080

CMD ["uv", "run", "python", "-m", "src.ortc.server"]
