locals {
  # CPU/memory split across the two containers (must sum to <= task_cpu/task_memory).
  # restapi is the heavy Java app; websockets is a tiny relay: it gets a small
  # fixed reservation and restapi takes the remainder.
  websockets_cpu    = 256
  websockets_memory = 256
  restapi_cpu       = var.task_cpu - local.websockets_cpu
  restapi_memory    = var.task_memory - local.websockets_memory

  # Readiness path on the restapi management port (8091). This is a fixed Spring
  # Boot Actuator endpoint served at the root of the management port and is NOT
  # prefixed by the application context path (which only applies to the app port
  # 8081). See https://docs.camunda.io/docs/next/self-managed/components/hub/monitoring/#available-endpoints
  restapi_health_path = "/health/readiness"

  # CAMUNDA_LICENSE_KEY is injected into both containers when a secret is provided.
  license_secret_entry = var.license_secret_arn != "" ? [{ name = "CAMUNDA_LICENSE_KEY", valueFrom = var.license_secret_arn }] : []

  # Base env injected by the module into the restapi container.
  restapi_base_env = concat(
    [
      { name = "SERVER_SERVLET_CONTEXT_PATH", value = var.context_path },
      { name = "MANAGEMENT_SERVER_PORT", value = "8091" },
      { name = "ZEEBE_CLIENT_CONFIG_PATH", value = "/tmp/zeebe_client_cache.txt" },
      # Server-side Pusher: restapi publishes to the co-located websockets container over localhost.
      { name = "CAMUNDA_MODELER_PUSHER_HOST", value = "localhost" },
      { name = "CAMUNDA_MODELER_PUSHER_PORT", value = "8060" },
      { name = "RESTAPI_PUSHER_APP_ID", value = var.pusher_app_id },
    ],
    var.environment_variables,
  )

  # Base secrets injected by the module into the restapi container.
  restapi_base_secrets = concat(
    [
      { name = "RESTAPI_PUSHER_KEY", valueFrom = var.pusher_app_key_secret_arn },
      { name = "RESTAPI_PUSHER_SECRET", valueFrom = var.pusher_app_secret_secret_arn },
    ],
    local.license_secret_entry,
    var.secrets,
  )

  # Websockets container env.
  websockets_env = [
    { name = "APP_NAME", value = "Camunda Hub WebSockets" },
    { name = "PUSHER_APP_ID", value = var.pusher_app_id },
    { name = "PUSHER_APP_PATH", value = "${var.context_path}-ws" },
  ]

  # Websockets container secrets.
  websockets_secrets = concat(
    [
      { name = "PUSHER_APP_KEY", valueFrom = var.pusher_app_key_secret_arn },
      { name = "PUSHER_APP_SECRET", valueFrom = var.pusher_app_secret_secret_arn },
    ],
    local.license_secret_entry,
  )
}

resource "aws_ecs_task_definition" "camunda_hub" {
  family                   = "${var.prefix}-camunda-hub"
  execution_role_arn       = var.ecs_task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  runtime_platform {
    operating_system_family = var.task_operating_system_family
    cpu_architecture        = var.task_cpu_architecture
  }

  container_definitions = templatefile("${path.module}/templates/camunda-hub.json.tpl", {
    restapi_image            = var.restapi_image
    websockets_image         = var.websockets_image
    restapi_cpu              = local.restapi_cpu
    restapi_memory           = local.restapi_memory
    websockets_cpu           = local.websockets_cpu
    websockets_memory        = local.websockets_memory
    aws_region               = var.aws_region
    log_group_name           = var.log_group_name
    registry_credentials_arn = var.registry_credentials_arn
    context_path             = var.context_path
    restapi_health_path      = local.restapi_health_path

    restapi_env_json     = jsonencode(local.restapi_base_env)
    restapi_has_secrets  = length(local.restapi_base_secrets) > 0
    restapi_secrets_json = jsonencode(local.restapi_base_secrets)

    websockets_env_json     = jsonencode(local.websockets_env)
    websockets_has_secrets  = length(local.websockets_secrets) > 0
    websockets_secrets_json = jsonencode(local.websockets_secrets)
  })

  task_role_arn = aws_iam_role.ecs_task_role.arn

  volume {
    name = "tmp"
  }
}

resource "aws_ecs_service" "camunda_hub" {
  # ECS CreateService requires each target group in a load_balancer block to be
  # associated with a load balancer first; the listener rules do that attachment,
  # so the service must wait for them (they only share the target group otherwise,
  # which does not order the service after the rules).
  depends_on = [aws_lb_listener_rule.hub, aws_lb_listener_rule.hub_ws]

  name                              = "${var.prefix}-camunda-hub"
  cluster                           = var.ecs_cluster_id
  task_definition                   = aws_ecs_task_definition.camunda_hub.arn
  desired_count                     = var.task_desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = var.service_health_check_grace_period_seconds

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

  # Consume other services (orchestration cluster) via Service Connect; expose nothing.
  service_connect_configuration {
    enabled   = true
    namespace = var.s2s_cloudmap_namespace
  }

  dynamic "load_balancer" {
    for_each = {
      (aws_lb_target_group.restapi.arn)    = { name = "camunda-hub-restapi", port = 8081 }
      (aws_lb_target_group.websockets.arn) = { name = "camunda-hub-websockets", port = 8060 }
    }
    content {
      target_group_arn = load_balancer.key
      container_name   = load_balancer.value.name
      container_port   = load_balancer.value.port
    }
  }

  wait_for_steady_state = var.wait_for_steady_state

  timeouts {
    create = var.service_timeouts.create
    update = var.service_timeouts.update
    delete = var.service_timeouts.delete
  }
}
