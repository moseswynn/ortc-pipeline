#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
TAG="${TAG:-latest}"

echo "==> Seeding database..."
uv run python -m src.db

echo "==> Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_BASE"

echo "==> Building and pushing rest-server..."
docker build -f docker/rest-server.Dockerfile -t "${ECR_BASE}/ortc-pipeline/rest-server:${TAG}" .
docker push "${ECR_BASE}/ortc-pipeline/rest-server:${TAG}"

echo "==> Building and pushing ortc-server..."
docker build -f docker/ortc-server.Dockerfile -t "${ECR_BASE}/ortc-pipeline/ortc-server:${TAG}" .
docker push "${ECR_BASE}/ortc-pipeline/ortc-server:${TAG}"

echo "==> Building and pushing bench..."
docker build -f docker/bench.Dockerfile -t "${ECR_BASE}/ortc-pipeline/bench:${TAG}" .
docker push "${ECR_BASE}/ortc-pipeline/bench:${TAG}"

echo "==> Done! Images pushed to ECR."
echo "  rest-server: ${ECR_BASE}/ortc-pipeline/rest-server:${TAG}"
echo "  ortc-server: ${ECR_BASE}/ortc-pipeline/ortc-server:${TAG}"
echo "  bench:       ${ECR_BASE}/ortc-pipeline/bench:${TAG}"
