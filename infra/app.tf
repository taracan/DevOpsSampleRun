# app.tf: runs the backend container. ECR (image storage), ECS Fargate
# (runs it) and an Application Load Balancer (sends traffic to it).
#
#   CloudFront --/api/*--> ALB (public subnets, port 80)
#                           |  forwards to healthy targets only
#                           v
#                   ECS service (private subnets): 1 Fargate task
#                   running the backend image from ECR on port 8000
#                           |
#                           v
#                       RDS (data.tf)
#
# Pieces:
#   - ECR repository: a private Docker registry. Images are pushed here,
#     by hand the first time, by GitHub Actions in step 10.
#   - ECS cluster: a named group of tasks. With Fargate there are no
#     servers to manage; AWS runs each container on demand.
#   - Task definition: the recipe for one container: image, CPU/memory,
#     port, environment variables, and the DB password, which ECS reads
#     from Secrets Manager at start-up and passes in as DB_PASSWORD.
#   - Service: keeps 1 copy of the task running, replaces it if it
#     crashes, and registers it with the load balancer. If a new
#     deployment can't become healthy, the circuit breaker rolls back.
#   - ALB, target group and listener: receive HTTP on port 80 and
#     forward to the task's port 8000. The ALB health-checks /health and
#     only sends traffic to tasks that answer.
#   - Log group: the container's output (stdout/stderr) goes to
#     CloudWatch Logs, kept for 7 days.
#
# The image tag is "latest": every deploy pushes a new latest and tells
# the service to restart (force new deployment).
#
# Cost: ALB about $16/month; Fargate (0.25 vCPU, 0.5 GB, ARM64) about $7/month.

# ---------- ECR ----------
resource "aws_ecr_repository" "backend" {
  name         = local.ecr_repo
  force_delete = true # dev only: destroy even if it holds images

  image_scanning_configuration {
    scan_on_push = true # check each pushed image for known vulnerabilities
  }
}

# ---------- Logs ----------
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name}-backend"
  retention_in_days = 7
}

# ---------- ECS ----------
resource "aws_ecs_cluster" "main" {
  name = local.cluster
}

resource "aws_ecs_task_definition" "backend" {
  family                   = local.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # each task gets its own network interface
  cpu                      = 256      # 0.25 vCPU
  memory                   = 512      # MB
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64" # matches images built on Apple Silicon
  }

  container_definitions = jsonencode([{
    name         = "backend"
    image        = "${aws_ecr_repository.backend.repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = local.app_port }]

    # Plain settings (app/core/config.py reads these).
    environment = [
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "DB_PORT", value = tostring(local.db_port) },
      { name = "DB_USER", value = aws_db_instance.main.username },
      { name = "DB_NAME", value = aws_db_instance.main.db_name },
      { name = "REPORTS_BUCKET", value = aws_s3_bucket.reports.bucket },
    ]

    # Secret: the "password" field of the RDS-managed secret.
    secrets = [
      { name = "DB_PASSWORD", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.backend.name
        awslogs-region        = local.region
        awslogs-stream-prefix = "backend"
      }
    }
  }])
}

resource "aws_ecs_service" "backend" {
  name            = local.service
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false # private subnet; internet via the NAT gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = local.app_port
  }

  # A failed deployment rolls back to the last working version.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]
}

# ---------- Load balancer ----------
resource "aws_lb" "main" {
  name               = local.name
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "backend" {
  name                 = "${local.name}-backend"
  port                 = local.app_port
  protocol             = "HTTP"
  target_type          = "ip" # Fargate tasks register by IP address
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30 # seconds to drain an old task during a deploy

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

# HTTP only: CloudFront handles HTTPS for visitors (step 8).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
