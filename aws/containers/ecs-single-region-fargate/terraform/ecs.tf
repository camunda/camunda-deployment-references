locals {
  env_lines = split("\n", templatefile("${path.module}/templates/core-environment", {
    opensearch_url = "https://${join("", module.opensearch_domain[*].opensearch_domain_endpoint)}"
  }))
  env_kv_pairs = [
    for line in local.env_lines : {
      name  = trim(split("=", line)[0], " ")
      value = trim(join("=", slice(split("=", line), 1, length(split("=", line)))), " ")
    }
  ]
}

resource "aws_ecs_cluster" "ecs" {
  name = "${var.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "core" {
  family                   = "${var.prefix}-core"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 4096
  memory                   = 8192
  container_definitions = templatefile("./templates/core.json.tpl", {
    core_image     = "camunda/camunda:SNAPSHOT"
    core_cpu       = 4096
    core_memory    = 8192
    aws_region     = "eu-central-1"
    prefix         = var.prefix
    opensearch_url = "https://${join("", module.opensearch_domain[*].opensearch_domain_endpoint)}"
    env_vars_json = jsonencode(local.env_kv_pairs)
    docker_hub_credentials_arn = var.docker_hub_username != "" ? aws_secretsmanager_secret.docker_hub_credentials[0].arn : ""
  })

  task_role_arn = aws_iam_role.ecs_task_role.arn

  volume {
    name                = "camunda-volume"
    
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.efs.id
      root_directory = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.camunda_data.id
        iam             = "ENABLED"
      }
    }
  }

}

resource "aws_ecs_service" "core" {
  name            = "${var.prefix}-core-service"
  cluster         = aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.core.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Enable execute command for debugging
  enable_execute_command = true

  deployment_maximum_percent = 100
  deployment_minimum_healthy_percent = 0

  network_configuration {
    subnets = module.vpc.private_subnets
    security_groups = [
      aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
      aws_security_group.allow_package_80_443.id,
      aws_security_group.efs.id,
    ]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.discovery.arn
  }

  # Ensure EFS mount targets are ready before starting service
  depends_on = [
    aws_efs_mount_target.efs_mounts,
    aws_efs_access_point.camunda_data
  ]

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "${var.prefix}-core"
    container_port   = 8080
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_9600.arn
    container_name   = "${var.prefix}-core"
    container_port   = 9600
  }

  # load_balancer {
  #   target_group_arn = aws_lb_target_group.main_9090.arn
  #   container_name   = "${var.prefix}-connectors"
  #   container_port   = 9090
  # }

  // TODO: Move to NLB, as ALB still doesn't work that way
  load_balancer {
    target_group_arn = aws_lb_target_group.main_26500.arn
    container_name   = "${var.prefix}-core"
    container_port   = 26500
  }
}
