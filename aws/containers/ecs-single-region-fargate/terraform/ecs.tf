locals {
  env_lines = split("\n", templatefile("${path.module}/templates/core-environment", {
    opensearch_url = "https://${join("", module.opensearch_domain[*].opensearch_domain_endpoint)}"
  }))
  env_kv_pairs = [
    for line in local.env_lines : {
      name  = trim(split("=", line)[0], " ")
      value = trim(join("=", slice(split("=", line), 1, length(split("=", line)))), " ")
    }
    if length(split("=", line)) > 1  # Filter out lines without '='
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
  count = var.camunda_count

  family                   = "${var.prefix}-core-${count.index}"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 4096
  memory                   = 8192
  container_definitions = templatefile("./templates/core.json.tpl", {
    core_image  = "registry.camunda.cloud/team-zeebe/camunda-ecs:8.9.0.${var.ecs-revision}"
    # core_image  = "registry.camunda.cloud/team-hto/camunda/camunda:ecs-lease-hack-v4"
    core_cpu    = 4096
    core_memory = 8192
    aws_region  = "eu-north-1"
    prefix      = var.prefix
    env_vars_json = jsonencode(concat([
      {
        name  = "ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS"
        value = join(",", [for i in range(var.camunda_count) : "${var.prefix}-ecs-${i}.${var.prefix}.service.local:26502"])
      },
      {
        name  = "ZEEBE_BROKER_CLUSTER_CLUSTERSIZE"
        value = "3"
      },
      {
        name  = "ZEEBE_BROKER_CLUSTER_REPLICATIONFACTOR"
        value = "3"
      },
      # {
      #   name  = "ZEEBE_BROKER_NETWORK_ADVERTISEDHOST"
      #   value = "0.0.0.0"
      #   # value = "${var.prefix}-ecs-${count.index}.${var.prefix}.service.local"
      # },
      {
        name  = "ZEEBE_BROKER_LEASECONFIG_SECRETKEY"
        value = aws_iam_access_key.s3_user_key.secret
      },
      {
        name  = "ZEEBE_BROKER_LEASECONFIG_BUCKETNAME"
        value = aws_s3_bucket.main.id
      },
      {
        name  = "ZEEBE_BROKER_LEASECONFIG_ACCESSKEY"
        value = aws_iam_access_key.s3_user_key.id
      }
    ], local.env_kv_pairs))
    docker_hub_credentials_arn = var.docker_hub_username != "" ? aws_secretsmanager_secret.docker_hub_credentials[0].arn : ""
  })

  task_role_arn = aws_iam_role.ecs_task_role.arn

  volume {
    name = "camunda-volume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs[count.index].id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.camunda_data[count.index].id
        iam             = "ENABLED"
      }
    }
  }

}

resource "aws_ecs_service" "core" {
  count = var.camunda_count

  name                              = "${var.prefix}-core-service-${count.index}"
  cluster                           = aws_ecs_cluster.ecs.id
  task_definition                   = aws_ecs_task_definition.core[count.index].arn
  desired_count                     = 3
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 300

  # Enable execute command for debugging
  enable_execute_command = true

  deployment_maximum_percent         = 100
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
    registry_arn = aws_service_discovery_service.discovery[count.index].arn
  }

  # We register all services to same target group, this will then do the load balancing for our services
  load_balancer {
    target_group_arn = aws_lb_target_group.main[0].arn
    container_name   = "${var.prefix}-core"
    container_port   = 8080
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_9600[0].arn
    container_name   = "${var.prefix}-core"
    container_port   = 9600
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_26500[0].arn
    container_name   = "${var.prefix}-core"
    container_port   = 26500
  }
}
