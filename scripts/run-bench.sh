#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/../infra" && pwd)"

AWS_REGION="${AWS_REGION:-us-east-1}"
RUN_ID="${RUN_ID:-$(uuidgen)}"

echo "==> Benchmark run ID: $RUN_ID"

# Read Terraform outputs
CLUSTER=$(terraform -chdir="$INFRA_DIR" output -raw ecs_cluster_name)
BENCH_REST_TASK=$(terraform -chdir="$INFRA_DIR" output -raw bench_rest_task_definition)
BENCH_ORTC_TASK=$(terraform -chdir="$INFRA_DIR" output -raw bench_ortc_task_definition)
PRIVATE_SUBNETS=$(terraform -chdir="$INFRA_DIR" output -json private_subnets | jq -r 'join(",")')
PUBLIC_SUBNETS=$(terraform -chdir="$INFRA_DIR" output -json public_subnets | jq -r 'join(",")')
SG=$(terraform -chdir="$INFRA_DIR" output -raw ecs_security_group)
S3_BUCKET=$(terraform -chdir="$INFRA_DIR" output -raw s3_results_bucket)

REST_ALB=$(terraform -chdir="$INFRA_DIR" output -raw rest_alb_url)

echo "==> Running REST benchmark task..."
REST_TASK_ARN=$(aws ecs run-task \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --task-definition "$BENCH_REST_TASK" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --overrides "{\"containerOverrides\":[{\"name\":\"bench-rest\",\"command\":[\"--mode\",\"rest\",\"--server-host\",\"${REST_ALB}\",\"--batch-sizes\",\"1000,10000,100000\",\"--output\",\"s3://${S3_BUCKET}/data\",\"--run-id\",\"${RUN_ID}\"]}]}" \
  --count 1 \
  --query 'tasks[0].taskArn' --output text)

echo "  REST task: $REST_TASK_ARN"

echo "==> Finding ORTC server IP..."
ORTC_TASK_ARN=$(aws ecs list-tasks \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --service-name ortc-server \
  --query 'taskArns[0]' --output text)

ORTC_ENI=$(aws ecs describe-tasks \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --tasks "$ORTC_TASK_ARN" \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)

ORTC_IP=$(aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --network-interface-ids "$ORTC_ENI" \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

echo "  ORTC server IP: $ORTC_IP"

echo "==> Running ORTC benchmark task..."
ORTC_BENCH_ARN=$(aws ecs run-task \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --task-definition "$BENCH_ORTC_TASK" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$PUBLIC_SUBNETS],securityGroups=[$SG],assignPublicIp=ENABLED}" \
  --overrides "{\"containerOverrides\":[{\"name\":\"bench-ortc\",\"command\":[\"--mode\",\"ortc\",\"--server-host\",\"http://${ORTC_IP}:8080\",\"--batch-sizes\",\"1000,10000,100000\",\"--output\",\"s3://${S3_BUCKET}/data\",\"--run-id\",\"${RUN_ID}\"]}]}" \
  --count 1 \
  --query 'tasks[0].taskArn' --output text)

echo "  ORTC task: $ORTC_BENCH_ARN"

echo "==> Waiting for tasks to complete..."
aws ecs wait tasks-stopped --region "$AWS_REGION" --cluster "$CLUSTER" --tasks "$REST_TASK_ARN" "$ORTC_BENCH_ARN"

echo "==> Tasks completed."
echo "    Run ID:    $RUN_ID"
echo "    S3 data:   s3://${S3_BUCKET}/data/${RUN_ID}/"
echo "    Check CloudWatch logs (/ecs/ortc-pipeline/bench) for benchmark metrics."
