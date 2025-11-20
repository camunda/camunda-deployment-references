
resource "aws_ecs_task_definition" "orchestration_cluster" {
  family                   = "${var.prefix}-orchestration-cluster"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 4096
  memory                   = 8192
  container_definitions = templatefile("${path.module}/templates/orchestration-cluster.json.tpl", {
    image                    = var.image
    cpu                      = var.task_cpu
    memory                   = var.task_memory
    aws_region               = var.aws_region
    prefix                   = var.prefix
    registry_credentials_arn = var.registry_credentials_arn
    env_vars_json = jsonencode(concat([
      {
        name  = "CAMUNDA_CLUSTER_INITIALCONTACTPOINTS"
        value = "orchestration-cluster.${var.prefix}.service.local:26502"
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
  deployment_minimum_healthy_percent = 67

  network_configuration {
    subnets = concat(
      var.vpc_private_subnets,
      var.vpc_public_subnets, # TODO: double check whether public is really needed
    )
    security_groups  = var.service_security_group_ids
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.discovery.arn
  }

  # TODO: Dynamic?
  # load_balancer {
  #   target_group_arn = aws_lb_target_group.main.arn
  #   container_name   = "orchestration-cluster"
  #   container_port   = 8080
  # }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_9600.arn
    container_name   = "orchestration-cluster"
    container_port   = 9600
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_26500.arn
    container_name   = "orchestration-cluster"
    container_port   = 26500
  }
}
