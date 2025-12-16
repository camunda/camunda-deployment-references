
resource "aws_ecs_task_definition" "connectors" {
  family                   = "${var.prefix}-connectors"
  execution_role_arn       = var.ecs_task_execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  container_definitions = templatefile("${path.module}/templates/connectors.json.tpl", {
    image                    = var.image
    cpu                      = var.task_cpu
    memory                   = var.task_memory
    aws_region               = var.aws_region
    registry_credentials_arn = var.registry_credentials_arn
    log_group_name           = var.log_group_name # TODO: fix logging, they have a different pattern than OC :(
    env_vars_json = jsonencode(concat([

    ], var.environment_variables))
  })

  task_role_arn = aws_iam_role.ecs_task_role.arn

}

resource "aws_ecs_service" "connectors" {
  name                              = "${var.prefix}-connectors"
  cluster                           = var.ecs_cluster_id
  task_definition                   = aws_ecs_task_definition.connectors.arn
  desired_count                     = var.task_desired_count #3
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 300

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
