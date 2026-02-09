
locals {
  # Base environment variables shared between main container and restore init container
  base_environment_variables = [
    # Graceful shutdown
    # Allow the Orchestration Cluster to shut down gracefully to release S3 leases
    # AWS Scheduler can sometimes be quicker to kill the task than the default 30s timeout
    {
      name  = "SPRING_LIFECYCLE_TIMEOUTPERSHUTDOWNPHASE"
      value = "5s"
    },
    # EFS Mount
    {
      name  = "ZEEBE_BROKER_DATA_DIRECTORY"
      value = "/usr/local/camunda/data"
    },
    # Zeebe Cluster Configuration
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
  ]
}

resource "aws_ecs_task_definition" "orchestration_cluster" {
  family                   = "${var.prefix}-orchestration-cluster"
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
    precondition {
      condition     = var.restore_backup_id == "" || var.restore_container_image != ""
      error_message = "When restore_backup_id is set, restore_container_image must be provided."
    }
  }

  container_definitions = templatefile("${path.module}/templates/orchestration-cluster.json.tpl", {
    image                    = var.image
    cpu                      = var.task_cpu
    memory                   = var.task_memory
    aws_region               = var.aws_region
    log_group_name           = aws_cloudwatch_log_group.orchestration_cluster_log_group.name
    registry_credentials_arn = var.registry_credentials_arn
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
            "awslogs-group"         = aws_cloudwatch_log_group.orchestration_cluster_log_group.name
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "orchestration-cluster-init"
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

    restore_container_enabled = var.restore_backup_id != ""
    restore_container_name    = "restore"
    restore_container_json = jsonencode(merge(
      {
        name      = "restore"
        image     = var.restore_container_image
        essential = false
        mountPoints = [
          {
            sourceVolume  = "camunda-volume"
            containerPath = "/usr/local/camunda/data"
            readOnly      = false
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.orchestration_cluster_log_group.name
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "orchestration-cluster-restore"
          }
        }
      },
      var.registry_credentials_arn != "" ? {
        repositoryCredentials = {
          credentialsParameter = var.registry_credentials_arn
        }
      } : {},
      length(var.restore_container_entrypoint) > 0 ? { entryPoint = var.restore_container_entrypoint } : {},
      # Include same environment variables as main container plus BACKUP_ID
      {
        environment = concat(
          [
            { name = "BACKUP_ID", value = var.restore_backup_id },
          ],
          local.base_environment_variables,
          var.environment_variables
        )
      },
      length(concat(var.secrets, var.restore_container_secrets)) > 0 ? { secrets = concat(var.secrets, var.restore_container_secrets) } : {}
    ))

    env_vars_json = jsonencode(concat(local.base_environment_variables, var.environment_variables))
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

  dynamic "volume" {
    for_each = var.init_container_enabled ? [1] : []
    content {
      name = "init-config"
    }
  }

}

resource "aws_ecs_service" "orchestration_cluster" {
  name                              = "${var.prefix}-orchestration-cluster"
  cluster                           = var.ecs_cluster_id # aws_ecs_cluster.ecs.id
  task_definition                   = aws_ecs_task_definition.orchestration_cluster.arn
  desired_count                     = var.task_desired_count #3
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = var.service_health_check_grace_period_seconds

  # Enable execute command for debugging
  enable_execute_command = var.task_enable_execute_command # true
  force_new_deployment   = var.service_force_new_deployment

  # Don't overprovision as it won't become healthy
  # Keep 2/3rds of desired count running during deployments to maintain quorum
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 66

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

    # dynamic for_each is not deterministic and we consume the outputs by index
    service {
      port_name      = "grpc"
      discovery_name = "orchestration-cluster-grpc"
      client_alias {
        port     = 26500
        dns_name = "orchestration-cluster-grpc"
      }
    }

    service {
      port_name      = "internal-api"
      discovery_name = "orchestration-cluster-sc"
      client_alias {
        port     = 26502
        dns_name = "orchestration-cluster-sc"
      }
    }

    service {
      port_name      = "rest"
      discovery_name = "orchestration-cluster-rest"
      client_alias {
        port     = 8080
        dns_name = "orchestration-cluster-rest"
      }
    }
  }

  # Dynamic load balancer configuration
  # Only include target groups that are attached to a load balancer
  dynamic "load_balancer" {
    for_each = merge(
      var.enable_alb_http_webapp_listener_rule ? { 8080 = aws_lb_target_group.main.arn } : {},
      var.enable_alb_http_management_listener_rule ? { 9600 = aws_lb_target_group.main_9600.arn } : {},
      var.enable_nlb_grpc_26500_listener ? { 26500 = aws_lb_target_group.main_26500.arn } : {}
    )
    content {
      target_group_arn = load_balancer.value
      container_name   = "orchestration-cluster"
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
