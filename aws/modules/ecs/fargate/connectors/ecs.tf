
resource "aws_ecs_task_definition" "connectors" {
  family                   = "${var.prefix}-connectors"
  execution_role_arn       = var.ecs_task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  runtime_platform {
    operating_system_family = var.task_operating_system_family
    cpu_architecture        = var.task_cpu_architecture
  }

  lifecycle {
    precondition {
      condition     = !var.init_container_enabled || var.init_container_image != ""
      error_message = "When init_container_enabled is true, init_container_image must be set."
    }
  }

  container_definitions = templatefile("${path.module}/templates/connectors.json.tpl", {
    image                    = var.image
    cpu                      = var.task_cpu
    memory                   = var.task_memory
    aws_region               = var.aws_region
    registry_credentials_arn = var.registry_credentials_arn
    log_group_name           = var.log_group_name
    has_secrets              = length(var.secrets) > 0
    secrets_json             = jsonencode(var.secrets)

    init_container_enabled = var.init_container_enabled
    init_container_name    = var.init_container_name
    init_container_json = jsonencode(merge(
      {
        name      = var.init_container_name
        image     = var.init_container_image
        essential = false
        mountPoints = [
          {
            sourceVolume  = "init-config"
            containerPath = "/config"
            readOnly      = false
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = var.log_group_name
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "connectors-init"
          }
        }
      },
      var.registry_credentials_arn != "" ? {
        repositoryCredentials = {
          credentialsParameter = var.registry_credentials_arn
        }
      } : {},
      length(var.init_container_command) > 0 ? { command = var.init_container_command } : {},
      length(var.init_container_environment_variables) > 0 ? { environment = var.init_container_environment_variables } : {},
      length(var.init_container_secrets) > 0 ? { secrets = var.init_container_secrets } : {}
    ))

    env_vars_json = jsonencode(concat([
      # Setting the context path to allow ALB routing
      {
        name  = "SERVER_SERVLET_CONTEXT_PATH"
        value = "/connectors"
      },
    ], var.environment_variables))
  })

  task_role_arn = aws_iam_role.ecs_task_role.arn

  dynamic "volume" {
    for_each = var.init_container_enabled ? [1] : []
    content {
      name = "init-config"
    }
  }

}

resource "aws_ecs_service" "connectors" {
  name                              = "${var.prefix}-connectors"
  cluster                           = var.ecs_cluster_id
  task_definition                   = aws_ecs_task_definition.connectors.arn
  desired_count                     = var.task_desired_count #3
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = var.service_health_check_grace_period_seconds

  # Enable execute command for debugging
  enable_execute_command = var.task_enable_execute_command # true
  force_new_deployment   = var.service_force_new_deployment

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50

  network_configuration {
    subnets          = var.vpc_private_subnets
    security_groups  = var.service_security_group_ids
    assign_public_ip = false
  }

  # ECS Service Connect for internal service-to-service communication
  # Don't expose anything but consume other services
  service_connect_configuration {
    enabled   = true
    namespace = var.s2s_cloudmap_namespace
  }

  # Dynamic load balancer configuration
  dynamic "load_balancer" {
    for_each = {
      8080 = aws_lb_target_group.main.arn
    }
    content {
      target_group_arn = load_balancer.value
      container_name   = "connectors"
      container_port   = load_balancer.key
    }
  }

  wait_for_steady_state = var.wait_for_steady_state

  timeouts {
    create = var.service_timeouts.create
    update = var.service_timeouts.update
    delete = var.service_timeouts.delete
  }
}
