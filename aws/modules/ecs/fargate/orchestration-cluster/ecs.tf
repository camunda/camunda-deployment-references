
resource "aws_ecs_task_definition" "orchestration_cluster" {
  family                   = "${var.prefix}-orchestration-cluster"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  container_definitions = templatefile("${path.module}/templates/orchestration-cluster.json.tpl", {
    image                    = var.image
    cpu                      = var.task_cpu
    memory                   = var.task_memory
    aws_region               = var.aws_region
    log_group_name           = aws_cloudwatch_log_group.orchestration_cluster_log_group.name
    registry_credentials_arn = var.registry_credentials_arn
    env_vars_json = jsonencode(concat([
      {
        name  = "CAMUNDA_CLUSTER_INITIALCONTACTPOINTS"
        value = "orchestration-cluster-sc:26502"
      },
      {
        name  = "CAMUNDA_CLUSTER_SIZE"
        value = tostring(var.task_desired_count)
      },
      # Node Id Provider - ECS specific
      {
        name  = "CAMUNDA_CLUSTER_NODEIDPROVIDER_TYPE"
        value = "s3"
      },
      {
        name  = "CAMUNDA_CLUSTER_NODEIDPROVIDER_S3_BUCKETNAME"
        value = aws_s3_bucket.main.id
      },
      {
        name  = "CAMUNDA_CLUSTER_NODEIDPROVIDER_S3_LEASEDURATION"
        value = "PT15S"
      },
      {
        name  = "CAMUNDA_CLUSTER_NODEIDPROVIDER_S3_REGION"
        value = var.aws_region
      }
    ], var.environment_variables))
  })

  task_role_arn = aws_iam_role.ecs_task_role.arn

  volume {
    name = "camunda-volume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.camunda_data.id
        iam             = "ENABLED"
      }
    }
  }

}

resource "aws_ecs_service" "orchestration_cluster" {
  name                              = "${var.prefix}-orchestration-cluster"
  cluster                           = var.ecs_cluster_id # aws_ecs_cluster.ecs.id
  task_definition                   = aws_ecs_task_definition.orchestration_cluster.arn
  desired_count                     = var.task_desired_count #3
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 300

  # Enable execute command for debugging
  enable_execute_command = var.task_enable_execute_command # true
  force_new_deployment   = var.service_force_new_deployment

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 33

  network_configuration {
    subnets          = var.vpc_private_subnets
    security_groups  = var.service_security_group_ids
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.discovery.arn
  }

  # ECS Service Connect for internal service-to-service communication
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.service_connect.arn

    service {
      port_name      = "internal-api"
      discovery_name = "orchestration-cluster-sc"
      client_alias {
        port     = 26502
        dns_name = "orchestration-cluster-sc"
      }
    }
  }

  # Dynamic load balancer configuration
  dynamic "load_balancer" {
    for_each = {
      # 8080 = aws_lb_target_group.main.arn  # Commented out - uncomment when needed
      9600  = aws_lb_target_group.main_9600.arn
      26500 = aws_lb_target_group.main_26500.arn
    }
    content {
      target_group_arn = load_balancer.value
      container_name   = "orchestration-cluster"
      container_port   = load_balancer.key
    }
  }
}
