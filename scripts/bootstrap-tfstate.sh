#!/usr/bin/env bash
set -euo pipefail

# Creates the S3 bucket used for Terraform remote state.
# Run this once before the first `terraform init`.

AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET_NAME="ortc-pipeline-tfstate"

echo "==> Creating Terraform state bucket: $BUCKET_NAME"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "  Bucket already exists, skipping."
else
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION"
  fi
  echo "  Bucket created."
fi

aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled
echo "  Versioning enabled."

aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
echo "  Encryption enabled."

aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "  Public access blocked."

echo "==> Done. You can now run: cd infra && terraform init"
