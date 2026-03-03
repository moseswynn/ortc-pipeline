# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.project_name
}

# CloudWatch log groups
resource "aws_cloudwatch_log_group" "rest_server" {
  name              = "/ecs/${var.project_name}/rest-server"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "ortc_server" {
  name              = "/ecs/${var.project_name}/ortc-server"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "bench" {
  name              = "/ecs/${var.project_name}/bench"
  retention_in_days = 7
}

# IAM — ECS task execution role
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM — Bench task role (needs S3 write)
resource "aws_iam_role" "bench_task" {
  name = "${var.project_name}-bench-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "bench_s3" {
  name = "${var.project_name}-bench-s3"
  role = aws_iam_role.bench_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject"]
      Resource = "${aws_s3_bucket.results.arn}/*"
    }]
  })
}

# IAM — Server task role (minimal)
resource "aws_iam_role" "server_task" {
  name = "${var.project_name}-server-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# ALB for REST server
resource "aws_lb" "rest" {
  name               = "${var.project_name}-rest-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "rest" {
  name        = "${var.project_name}-rest-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "rest" {
  load_balancer_arn = aws_lb.rest.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rest.arn
  }
}

# REST Server — Task Definition + Service
resource "aws_ecs_task_definition" "rest_server" {
  family                   = "${var.project_name}-rest-server"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.server_task.arn

  container_definitions = jsonencode([{
    name      = "rest-server"
    image     = var.rest_server_image
    essential = true

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.rest_server.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "rest"
      }
    }
  }])
}

resource "aws_ecs_service" "rest_server" {
  name            = "rest-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rest_server.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rest.arn
    container_name   = "rest-server"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.rest]
}

# ORTC Server — Task Definition + Service (public IP for ICE)
resource "aws_ecs_task_definition" "ortc_server" {
  family                   = "${var.project_name}-ortc-server"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.server_task.arn

  container_definitions = jsonencode([{
    name      = "ortc-server"
    image     = var.ortc_server_image
    essential = true

    portMappings = [
      {
        containerPort = 8080
        protocol      = "tcp"
      },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ortc_server.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ortc"
      }
    }
  }])
}

resource "aws_ecs_service" "ortc_server" {
  name            = "ortc-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ortc_server.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
}

# Bench REST — Task Definition (one-shot)
resource "aws_ecs_task_definition" "bench_rest" {
  family                   = "${var.project_name}-bench-rest"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.bench_task.arn

  container_definitions = jsonencode([{
    name      = "bench-rest"
    image     = var.bench_image
    essential = true

    command = [
      "--mode", "rest",
      "--server-host", "http://${aws_lb.rest.dns_name}",
      "--batch-sizes", var.bench_batch_sizes,
      "--output", "s3://${aws_s3_bucket.results.id}/data",
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.bench.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "bench-rest"
      }
    }
  }])
}

# Bench ORTC — Task Definition (one-shot)
resource "aws_ecs_task_definition" "bench_ortc" {
  family                   = "${var.project_name}-bench-ortc"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.bench_task.arn

  container_definitions = jsonencode([{
    name      = "bench-ortc"
    image     = var.bench_image
    essential = true

    # server-host will be overridden at run time via run-bench.sh
    command = [
      "--mode", "ortc",
      "--server-host", "http://ORTC_SERVER_IP:8080",
      "--batch-sizes", var.bench_batch_sizes,
      "--output", "s3://${aws_s3_bucket.results.id}/data",
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.bench.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "bench-ortc"
      }
    }
  }])
}
