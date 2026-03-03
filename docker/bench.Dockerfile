FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libavcodec-dev libavformat-dev libavutil-dev \
        libopus-dev libvpx-dev pkg-config gcc && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY src/ src/

RUN uv sync --frozen --no-dev

ENTRYPOINT ["uv", "run", "python", "-m", "src.bench"]
