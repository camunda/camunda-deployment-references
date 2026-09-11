resource "aws_ecs_task_definition" "management_identity" {
  family                   = "${var.prefix}-management-identity"
  execution_role_arn       = var.ecs_task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  runtime_platform {
    operating_system_family = var.task_operating_system_family
    cpu_architecture        = var.task_cpu_architecture
  }

  container_definitions = templatefile("${path.module}/templates/management-identity.json.tpl", {
    image                    = var.image
    cpu                      = var.task_cpu
    memory                   = var.task_memory
    aws_region               = var.aws_region
    registry_credentials_arn = var.registry_credentials_arn
    log_group_name           = var.log_group_name
    has_secrets              = length(var.secrets) > 0
    secrets_json             = jsonencode(var.secrets)
    env_vars_json            = jsonencode(var.environment_variables)
  })

  task_role_arn = aws_iam_role.ecs_task_role.arn
}

resource "aws_ecs_service" "management_identity" {
  name                              = "${var.prefix}-management-identity"
  cluster                           = var.ecs_cluster_id
  task_definition                   = aws_ecs_task_definition.management_identity.arn
  desired_count                     = var.task_desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = var.enable_alb_http_webapp_listener_rule ? var.service_health_check_grace_period_seconds : null

  enable_execute_command = var.task_enable_execute_command
  force_new_deployment   = var.service_force_new_deployment

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50

  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  network_configuration {
    subnets          = var.vpc_private_subnets
    security_groups  = var.service_security_group_ids
    assign_public_ip = false
  }

  # ECS Service Connect: expose Management Identity so future consumers
  # (Hub / Optimize / Console / Web Modeler) can resolve it at "identity:8084".
  service_connect_configuration {
    enabled   = true
    namespace = var.s2s_cloudmap_namespace

    service {
      port_name      = "http"
      discovery_name = "identity"
      client_alias {
        port     = 8084
        dns_name = "identity"
      }
    }
  }

  # ALB attachment is opt-in (off for the MVP). When disabled, no target group
  # exists and this block is empty, so the service runs without a load balancer.
  dynamic "load_balancer" {
    for_each = var.enable_alb_http_webapp_listener_rule ? { 8084 = aws_lb_target_group.main[0].arn } : {}
    content {
      target_group_arn = load_balancer.value
      container_name   = "management-identity"
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
