variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "ortc-pipeline"
}

variable "rest_server_image" {
  description = "ECR image URI for the REST server"
  type        = string
}

variable "ortc_server_image" {
  description = "ECR image URI for the ORTC server"
  type        = string
}

variable "bench_image" {
  description = "ECR image URI for the benchmark client"
  type        = string
}

variable "bench_batch_sizes" {
  description = "Comma-separated batch sizes for benchmarks"
  type        = string
  default     = "1000,10000,100000"
}
