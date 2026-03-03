output "rest_alb_url" {
  description = "URL of the REST server ALB"
  value       = "http://${aws_lb.rest.dns_name}"
}

output "s3_results_bucket" {
  description = "S3 bucket for benchmark results"
  value       = aws_s3_bucket.results.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "bench_rest_task_definition" {
  description = "Bench REST task definition ARN"
  value       = aws_ecs_task_definition.bench_rest.arn
}

output "bench_ortc_task_definition" {
  description = "Bench ORTC task definition ARN"
  value       = aws_ecs_task_definition.bench_ortc.arn
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "ecs_security_group" {
  description = "ECS security group ID"
  value       = aws_security_group.ecs.id
}
