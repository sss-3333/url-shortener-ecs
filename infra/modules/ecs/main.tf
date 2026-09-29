locals {
  services = toset(["api", "worker", "dashboard"])

  # Pin each task to an exact image digest, not a tag, so what runs is exactly what was scanned
  images = {
    for name in local.services :
    name => "${data.aws_ecr_repository.this[name].repository_url}@${data.aws_ecr_image.this[name].image_digest}"
  }
}

data "aws_ecr_repository" "this" {
  for_each = local.services
  name     = "${var.project}-${each.key}"
}

# Latest pushed image. Only used when Terraform first creates the services; the pipeline deploys after that
data "aws_ecr_image" "this" {
  for_each        = local.services
  repository_name = data.aws_ecr_repository.this[each.key].name
  most_recent     = true
}

resource "aws_ecs_cluster" "this" {
  name = var.project
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.services

  name              = "/ecs/${var.project}-${each.key}"
  retention_in_days = var.log_retention_days
}

# ---- Task definitions ----

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_sizes["api"].cpu
  memory                   = var.task_sizes["api"].memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.api.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "api"
    image     = local.images["api"]
    essential = true

    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "PORT", value = "8080" },
      { name = "BASE_URL", value = var.api_base_url },
      { name = "REDIS_URL", value = var.redis_url },
      { name = "SQS_QUEUE_URL", value = var.sqs_queue_url },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "AWS_DEFAULT_REGION", value = var.aws_region },
    ]

    # Injected from Secrets Manager at startup, never stored in the task definition
    secrets = [{ name = "DATABASE_URL", valueFrom = var.database_url_secret_arn }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this["api"].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "api"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_sizes["worker"].cpu
  memory                   = var.task_sizes["worker"].memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.worker.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name                   = "worker"
    image                  = local.images["worker"]
    essential              = true
    readonlyRootFilesystem = true

    environment = [
      { name = "SQS_QUEUE_URL", value = var.sqs_queue_url },
      { name = "AWS_REGION", value = var.aws_region },
    ]

    secrets = [{ name = "DATABASE_URL", valueFrom = var.database_url_secret_arn }]

    # No ALB, so ECS checks health by running the binary's own health check (distroless has no curl)
    healthCheck = {
      command     = ["CMD", "/app", "-healthcheck"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this["worker"].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "worker"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "dashboard" {
  family                   = "${var.project}-dashboard"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_sizes["dashboard"].cpu
  memory                   = var.task_sizes["dashboard"].memory
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name                   = "dashboard"
    image                  = local.images["dashboard"]
    essential              = true
    readonlyRootFilesystem = true

    portMappings = [{ containerPort = 8081, protocol = "tcp" }]

    environment = [{ name = "PORT", value = "8081" }]

    secrets = [{ name = "DATABASE_URL", valueFrom = var.database_url_secret_arn }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this["dashboard"].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "dashboard"
      }
    }
  }])
}

# ---- Services ----
# All three ignore task_definition after creation: Terraform builds the service, the pipeline deploys new versions.

resource "aws_ecs_service" "api" {
  name            = "${var.project}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_ids["api"]]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.api_target_group_arn
    container_name   = "api"
    container_port   = 8080
  }

  health_check_grace_period_seconds = 60

  # Services run by CodeDeploy can't be scaled to zero first, so delete them directly on destroy
  force_delete = true

  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }
}

resource "aws_ecs_service" "dashboard" {
  name            = "${var.project}-dashboard"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.dashboard.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_ids["dashboard"]]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.dashboard_target_group_arn
    container_name   = "dashboard"
    container_port   = 8081
  }

  health_check_grace_period_seconds = 30

  lifecycle {
    ignore_changes = [task_definition]
  }
}

resource "aws_ecs_service" "worker" {
  name            = "${var.project}-worker"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_ids["worker"]]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}