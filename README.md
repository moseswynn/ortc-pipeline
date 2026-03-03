# ORTC Pipeline — Batch Data Transfer Comparison

Experimental comparison of two approaches for batch data movement:

1. **REST API** — Client polls a FastAPI server endpoint to fetch paginated JSON records over HTTP
2. **ORTC Data Channel** — Client connects via WebRTC/ORTC data channels (aiortc) and streams records over SCTP

Measures **latency** (time-to-first-record, total transfer time) and **throughput** (records/sec) across batch sizes of 1K, 10K, and 100K records. Both pipelines deploy to **AWS ECS Fargate** for realistic benchmarking, with transferred data written to **S3** and benchmark metrics uploaded as GitHub Actions artifacts.

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
├── scripts/                    # bootstrap-tfstate.sh, build-push.sh, run-bench.sh
└── .github/workflows/
    ├── deploy.yml              # Deploy (or destroy) infrastructure
    └── benchmark.yml           # Trigger benchmark runs
```

## GitHub Actions Workflows

All deployment and benchmarking is driven through GitHub Actions via **workflow dispatch**. You can fork this repository and add the required secrets/environment variables.

### Prerequisites

Add these repository secrets:

- `AWS_ACCESS_KEY_ID` — AWS access key with permissions for ECR, ECS, S3, VPC, IAM, CloudWatch
- `AWS_SECRET_ACCESS_KEY` — Corresponding secret key

Terraform state is stored in an S3 backend (`ortc-pipeline-tfstate` bucket), created automatically on first run.

### Deploy Infrastructure

**Workflow:** `Deploy Infrastructure` (`deploy.yml`)

1. Go to **Actions > Deploy Infrastructure > Run workflow**
2. Select `apply` and choose your AWS region
3. The workflow will:
   - Seed the SQLite database with 100K deterministic records
   - Build and push 3 Docker images to ECR (tagged with commit SHA)
   - Run `terraform apply` to create VPC, ECS cluster, ALB, S3 bucket, and all services

### Run Benchmarks

**Workflow:** `Run Benchmarks` (`benchmark.yml`)

1. Go to **Actions > Run Benchmarks > Run workflow**
2. Choose mode (`rest`, `ortc`, or `both`) and batch sizes
3. The workflow will:
   - Generate a unique **run ID** (UUID)
   - Launch ECS benchmark tasks that transfer data to S3 at `s3://bucket/data/{run-id}/{mode}/{batch_size}.ndjson`
   - Wait for tasks to complete
   - Extract metrics from CloudWatch logs
   - Upload metrics as a downloadable **artifact** (`benchmark-metrics-{run-id}`)
   - Display metrics in the **job summary**

Each benchmark run is isolated by its UUID, so results from multiple runs never collide.

### Tear Down

1. Go to **Actions > Deploy Infrastructure > Run workflow**
2. Select `destroy`
3. The workflow runs `terraform destroy` to remove all AWS resources

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
- **S3 remote backend** for Terraform state — persists across workflow runs without artifacts
