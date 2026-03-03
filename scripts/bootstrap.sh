#!/usr/bin/env bash
set -euo pipefail

# Bootstraps prerequisites that must exist before Terraform and Docker builds:
#   1. S3 bucket for Terraform remote state
#   2. ECR repositories for Docker images
#
# Idempotent — safe to run on every deploy.

AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET_NAME="ortc-pipeline-tfstate"
ECR_REPOS=(
  "ortc-pipeline/rest-server"
  "ortc-pipeline/ortc-server"
  "ortc-pipeline/bench"
)

# --- S3 state bucket ---
echo "==> Terraform state bucket: $BUCKET_NAME"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "  Already exists, skipping."
else
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION"
  fi
  echo "  Created."
fi

aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "  Versioning, encryption, and public access block configured."

# --- ECR repositories ---
echo "==> ECR repositories"

for repo in "${ECR_REPOS[@]}"; do
  if aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "  $repo — already exists"
  else
    aws ecr create-repository --repository-name "$repo" --region "$AWS_REGION" \
      --image-tag-mutability MUTABLE >/dev/null
    echo "  $repo — created"
  fi
done

echo "==> Bootstrap complete."
