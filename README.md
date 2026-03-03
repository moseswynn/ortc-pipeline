# ORTC Pipeline — Batch Data Transfer Comparison

Experimental comparison of two approaches for batch data movement:

1. **REST API** — Client polls a FastAPI server endpoint to fetch paginated JSON records over HTTP
2. **ORTC Data Channel** — Client connects via WebRTC/ORTC data channels (aiortc) and streams records over SCTP

Measures **latency** (time-to-first-record, total transfer time) and **throughput** (records/sec) across batch sizes of 1K, 10K, and 100K records. Both pipelines deploy to **AWS ECS Fargate** for realistic benchmarking, with results written to **S3**.

## Project Structure

```
ortc-pipeline/
├── pyproject.toml              # Dependencies (uv)
├── src/
│   ├── db.py                   # SQLite setup + synthetic data generation
│   ├── models.py               # Shared Pydantic models
│   ├── rest/
│   │   ├── server.py           # FastAPI server (pagination, rate limiting)
│   │   └── client.py           # Async httpx client
│   ├── ortc/
│   │   ├── server.py           # aiortc data channel server + aiohttp signaling
│   │   └── client.py           # aiortc data channel client
│   └── bench.py                # Benchmark runner CLI
├── docker/                     # Dockerfiles for rest-server, ortc-server, bench
├── infra/                      # Terraform (VPC, ECR, ECS, S3, IAM)
└── scripts/                    # build-push.sh, run-bench.sh
```

## Local Development

```bash
# Install dependencies
uv sync

# Seed the database (100K records)
uv run python -m src.db

# Start the REST server
uv run uvicorn src.rest.server:app --port 8000

# Start the ORTC server
uv run python -m src.ortc.server

# Run benchmarks locally
uv run python -m src.bench --mode rest --server-host http://localhost:8000 --batch-sizes 1000,10000
uv run python -m src.bench --mode ortc --server-host http://localhost:8080 --batch-sizes 1000,10000
```

## AWS Deployment

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5
- Docker

### Deploy

```bash
# 1. Build and push Docker images to ECR
#    (seeds DB, builds all 3 images, pushes to ECR)
scripts/build-push.sh

# 2. Stand up infrastructure
cd infra
terraform init
terraform apply \
  -var rest_server_image="<ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/ortc-pipeline/rest-server:latest" \
  -var ortc_server_image="<ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/ortc-pipeline/ortc-server:latest" \
  -var bench_image="<ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/ortc-pipeline/bench:latest"

# 3. Run benchmarks
cd ..
scripts/run-bench.sh
```

Results are written to the S3 bucket as JSON files (`rest-results.json`, `ortc-results.json`).

### Tear Down

```bash
cd infra && terraform destroy
```

## Metrics Collected

| Metric | Description |
|--------|-------------|
| `time_to_first_record_s` | Time from request start to receiving the first record |
| `total_transfer_time_s` | Total wall-clock time for the entire batch transfer |
| `records_per_sec` | Throughput (records received / total time) |

## Design Decisions

- **JSON serialization** for both pipelines — apples-to-apples comparison
- **SQLite pre-seeded in Docker images** — deterministic data, no startup delay, no external DB dependency
- **REST rate limiting** (50 req/s token bucket) and **page size cap** (1000) — simulates realistic API constraints; the overhead of pagination + backoff is part of what we're measuring
- **ORTC server on public subnet** with `assignPublicIp` — required for ICE connectivity without a TURN relay
- **Fargate** — no EC2 management, quick to spin up/down
