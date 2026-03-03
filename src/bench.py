import argparse
import asyncio
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

import boto3

from src.ortc.client import fetch_all_records as ortc_fetch
from src.rest.client import fetch_all_records as rest_fetch


def _upload_records_to_s3(records, s3_path: str) -> None:
    """Upload the actual record data to S3 as NDJSON."""
    if not s3_path.startswith("s3://"):
        raise ValueError(f"Invalid S3 path: {s3_path}")

    parts = s3_path[5:].split("/", 1)
    bucket = parts[0]
    key = parts[1] if len(parts) > 1 else "data.ndjson"

    s3 = boto3.client("s3")
    body = "\n".join(r.serialize() for r in records)
    s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/x-ndjson")
    print(f"Data uploaded to {s3_path} ({len(records)} records)")


async def run_benchmark(
    mode: str,
    server_host: str,
    batch_sizes: list[int],
    s3_output: str | None,
    run_id: str | None = None,
) -> list[dict]:
    run_id = run_id or str(uuid.uuid4())
    print(f"Benchmark run ID: {run_id}")

    all_metrics = []
    for size in batch_sizes:
        print(f"[{mode}] Benchmarking batch_size={size}...")
        if mode == "rest":
            records, metrics = await rest_fetch(server_host, batch_size=size)
        elif mode == "ortc":
            records, metrics = await ortc_fetch(server_host, batch_size=size)
        else:
            raise ValueError(f"Unknown mode: {mode}")

        metrics["run_id"] = run_id
        metrics["timestamp"] = datetime.now(timezone.utc).isoformat()
        all_metrics.append(metrics)
        print(f"  -> {metrics['records_received']} records in {metrics['total_transfer_time_s']}s "
              f"({metrics['records_per_sec']} rec/s, TTFR={metrics['time_to_first_record_s']}s)")

        if s3_output:
            key_base = s3_output.rstrip("/")
            data_key = f"{key_base}/{run_id}/{mode}/{size}.ndjson"
            _upload_records_to_s3(records, data_key)

    return all_metrics


def main():
    parser = argparse.ArgumentParser(description="ORTC Pipeline Benchmark Runner")
    parser.add_argument("--mode", choices=["rest", "ortc"], required=True)
    parser.add_argument("--server-host", required=True, help="Base URL of the server")
    parser.add_argument(
        "--batch-sizes",
        default="1000,10000,100000",
        help="Comma-separated batch sizes (default: 1000,10000,100000)",
    )
    parser.add_argument(
        "--output",
        help="S3 path for pipeline data output (s3://bucket/prefix)",
    )
    parser.add_argument(
        "--run-id",
        help="Benchmark run UUID (auto-generated if not provided)",
    )
    parser.add_argument(
        "--metrics",
        help="Local file path to write benchmark metrics JSON",
    )
    args = parser.parse_args()

    batch_sizes = [int(s.strip()) for s in args.batch_sizes.split(",")]
    results = asyncio.run(run_benchmark(
        args.mode, args.server_host, batch_sizes, args.output, args.run_id,
    ))

    # Always print metrics to stdout (captured by CloudWatch in ECS)
    metrics_json = json.dumps(results, indent=2)
    print(f"BENCH_METRICS_START\n{metrics_json}\nBENCH_METRICS_END")

    if args.metrics:
        Path(args.metrics).parent.mkdir(parents=True, exist_ok=True)
        Path(args.metrics).write_text(metrics_json)
        print(f"Metrics written to {args.metrics}")


if __name__ == "__main__":
    main()
