################################################################
#         Orchestration Cluster - Region 0 (owner)             #
################################################################

module "orchestration_cluster_region_0" {
  source = "../../../../modules/ecs/fargate/orchestration-cluster"

  prefix                   = "${local.infra.cluster_name}-r0-oc"
  ecs_cluster_id           = local.infra.ecs_cluster_region_0_id
  vpc_id                   = local.infra.vpc_region_0_id
  vpc_private_subnets      = local.infra.vpc_region_0_private_subnets
  aws_region               = data.aws_region.region_0.id
  image                    = var.camunda_image
  registry_credentials_arn = startswith(var.camunda_image, "registry.camunda.cloud/") ? local.infra.registry_credentials_region_0_arn : ""
  s3_force_destroy         = local.infra.s3_force_destroy

  # IAM Roles
  ecs_task_execution_role_arn = local.infra.ecs_task_execution_role_region_0_arn

  # Load Balancer configuration
  alb_listener_http_webapp_arn     = local.infra.alb_listener_http_webapp_region_0_arn
  alb_listener_http_management_arn = local.infra.alb_listener_http_management_region_0_arn
  nlb_arn                          = local.infra.nlb_grpc_region_0_arn

  enable_alb_http_webapp_listener_rule     = true
  enable_alb_http_management_listener_rule = false
  enable_nlb_grpc_26500_listener           = true

  # Dual-region cluster configuration
  task_desired_count                = local.brokers_per_region
  cluster_size                      = local.cluster_size
  replication_factor                = local.replication_factor
  partition_count                   = local.partition_count
  region_id                         = 0
  initial_contact_points            = "orchestration-cluster-sc:26502,${local.infra.region_1_nlb_raft_endpoint}:26502"
  internal_nlb_arn                  = local.infra.nlb_raft_region_0_arn
  enable_internal_nlb_raft_listener = true

  # Increase health check grace period for cross-region Raft formation
  service_health_check_grace_period_seconds = 1200

  environment_variables = concat(
    local.partitioning_env_vars,
    local.cluster_region_env_region_0,
    local.rdbms_env_vars,
    local.opensearch_env_vars_region_0,
    local.common_env_vars,
    [
      {
        name  = "CAMUNDA_DATA_BACKUP_S3_BUCKETNAME"
        value = local.infra.backup_bucket_region_0_name
      },
      {
        name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
        value = local.infra.backup_bucket_region_0_name
      },
    ]
  )

  secrets = [
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD"
      valueFrom = local.infra.admin_user_password_secret_region_0_arn
    },
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_PASSWORD"
      valueFrom = local.infra.connectors_password_secret_region_0_arn
    }
  ]

  service_security_group_ids = [
    local.infra.sg_camunda_ports_region_0_id,
    local.infra.sg_package_80_443_region_0_id,
    local.infra.sg_efs_region_0_id,
  ]
  efs_security_group_ids = [local.infra.sg_efs_region_0_id]

  extra_task_role_attachments = concat(
    local.infra.rds_db_connect_policy_region_0_arn != null ? [local.infra.rds_db_connect_policy_region_0_arn] : [],
    [local.infra.s3_backup_access_policy_region_0_arn],
  )

  # Allow Session Manager port-forwarding into a broker task for first-time
  # debugging (e.g. `aws ecs execute-command`, port-forward to 8080/9600).
  task_enable_execute_command = true

  # Cross-region Raft formation can take 15-20 min the first time the global
  # cluster comes up; bump above the 15m module default to avoid spurious
  # circuit-breaker rollbacks during initial deploy.
  service_circuit_breaker_enabled = false

  service_timeouts = {
    create = "30m"
    update = "30m"
    delete = "15m"
  }
}

################################################################
#        Orchestration Cluster - Region 1 (accepter)           #
################################################################

module "orchestration_cluster_region_1" {
  source = "../../../../modules/ecs/fargate/orchestration-cluster"

  providers = {
    aws = aws.accepter
  }

  prefix                   = "${local.infra.cluster_name}-r1-oc"
  ecs_cluster_id           = local.infra.ecs_cluster_region_1_id
  vpc_id                   = local.infra.vpc_region_1_id
  vpc_private_subnets      = local.infra.vpc_region_1_private_subnets
  aws_region               = data.aws_region.region_1.id
  image                    = var.camunda_image
  registry_credentials_arn = startswith(var.camunda_image, "registry.camunda.cloud/") ? local.infra.registry_credentials_region_1_arn : ""
  s3_force_destroy         = local.infra.s3_force_destroy

  # IAM Roles
  ecs_task_execution_role_arn = local.infra.ecs_task_execution_role_region_1_arn

  # Load Balancer configuration
  alb_listener_http_webapp_arn     = local.infra.alb_listener_http_webapp_region_1_arn
  alb_listener_http_management_arn = local.infra.alb_listener_http_management_region_1_arn
  nlb_arn                          = local.infra.nlb_grpc_region_1_arn

  enable_alb_http_webapp_listener_rule     = true
  enable_alb_http_management_listener_rule = false
  enable_nlb_grpc_26500_listener           = true

  # Dual-region cluster configuration
  task_desired_count                = local.brokers_per_region
  cluster_size                      = local.cluster_size
  replication_factor                = local.replication_factor
  partition_count                   = local.partition_count
  region_id                         = 1
  initial_contact_points            = "orchestration-cluster-sc:26502,${local.infra.region_0_nlb_raft_endpoint}:26502"
  internal_nlb_arn                  = local.infra.nlb_raft_region_1_arn
  enable_internal_nlb_raft_listener = true

  # Increase health check grace period for cross-region Raft formation
  service_health_check_grace_period_seconds = 1200

  environment_variables = concat(
    local.partitioning_env_vars,
    local.cluster_region_env_region_1,
    local.rdbms_env_vars,
    local.opensearch_env_vars_region_1,
    local.common_env_vars,
    [
      {
        name  = "CAMUNDA_DATA_BACKUP_S3_BUCKETNAME"
        value = local.infra.backup_bucket_region_1_name
      },
      {
        name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
        value = local.infra.backup_bucket_region_1_name
      },
    ]
  )

  secrets = [
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD"
      valueFrom = local.infra.admin_user_password_secret_region_1_arn
    },
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_PASSWORD"
      valueFrom = local.infra.connectors_password_secret_region_1_arn
    }
  ]

  service_security_group_ids = [
    local.infra.sg_camunda_ports_region_1_id,
    local.infra.sg_package_80_443_region_1_id,
    local.infra.sg_efs_region_1_id,
  ]
  efs_security_group_ids = [local.infra.sg_efs_region_1_id]

  extra_task_role_attachments = concat(
    local.infra.rds_db_connect_policy_region_1_arn != null ? [local.infra.rds_db_connect_policy_region_1_arn] : [],
    [local.infra.s3_backup_access_policy_region_1_arn],
  )

  # See region 0 comments above.
  task_enable_execute_command     = true
  service_circuit_breaker_enabled = false

  service_timeouts = {
    create = "30m"
    update = "30m"
    delete = "15m"
  }
}

################################################################
#              Connectors - Region 0 (owner)                   #
################################################################

module "connectors_region_0" {
  source = "../../../../modules/ecs/fargate/connectors"

  prefix                               = "${local.infra.cluster_name}-r0-oc"
  ecs_cluster_id                       = local.infra.ecs_cluster_region_0_id
  vpc_id                               = local.infra.vpc_region_0_id
  vpc_private_subnets                  = local.infra.vpc_region_0_private_subnets
  aws_region                           = data.aws_region.region_0.id
  image                                = var.connectors_image
  registry_credentials_arn             = "" # connectors image is on docker.io (public); no registry creds needed and passing the registry.camunda.cloud creds confuses ECS
  s2s_cloudmap_namespace               = module.orchestration_cluster_region_0.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = local.infra.alb_listener_http_webapp_region_0_arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster_region_0.log_group_name

  ecs_task_execution_role_arn = local.infra.ecs_task_execution_role_region_0_arn

  service_security_group_ids = [
    local.infra.sg_camunda_ports_region_0_id,
    local.infra.sg_package_80_443_region_0_id,
  ]

  environment_variables = concat(
    local.rdbms_env_vars,
    local.opensearch_env_vars_region_0,
    [
      # Only run connectors — disable broker, gateway, operate, tasklist via Spring profile
      {
        name  = "SPRING_PROFILES_ACTIVE"
        value = "connectors"
      },
      # Connectors client configuration
      {
        name  = "CAMUNDA_CLIENT_MODE",
        value = "self-managed"
      },
      {
        name  = "CAMUNDA_CLIENT_RESTADDRESS",
        value = "http://${module.orchestration_cluster_region_0.rest_service_connect}:8080"
      },
      {
        name  = "CAMUNDA_CLIENT_GRPCADDRESS",
        value = "http://${module.orchestration_cluster_region_0.grpc_service_connect}:26500"
      },
      {
        name  = "CAMUNDA_CLIENT_AUTH_METHOD"
        value = "basic"
      },
      {
        name  = "CAMUNDA_CLIENT_AUTH_USERNAME"
        value = "connectors"
      }
    ]
  )

  secrets = [
    {
      name      = "CAMUNDA_CLIENT_AUTH_PASSWORD"
      valueFrom = local.infra.connectors_password_secret_region_0_arn
    }
  ]

  task_desired_count = 1
  extra_task_role_attachments = concat(
    local.infra.rds_db_connect_policy_region_0_arn != null ? [local.infra.rds_db_connect_policy_region_0_arn] : [],
  )
  service_timeouts = {
    create = "30m"
    update = "30m"
    delete = "15m"
  }
}

################################################################
#             Connectors - Region 1 (accepter)                 #
################################################################

module "connectors_region_1" {
  source = "../../../../modules/ecs/fargate/connectors"

  providers = {
    aws = aws.accepter
  }

  prefix                               = "${local.infra.cluster_name}-r1-oc"
  ecs_cluster_id                       = local.infra.ecs_cluster_region_1_id
  vpc_id                               = local.infra.vpc_region_1_id
  vpc_private_subnets                  = local.infra.vpc_region_1_private_subnets
  aws_region                           = data.aws_region.region_1.id
  image                                = var.connectors_image
  registry_credentials_arn             = "" # connectors image is on docker.io (public); no registry creds needed and passing the registry.camunda.cloud creds confuses ECS
  s2s_cloudmap_namespace               = module.orchestration_cluster_region_1.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = local.infra.alb_listener_http_webapp_region_1_arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster_region_1.log_group_name

  ecs_task_execution_role_arn = local.infra.ecs_task_execution_role_region_1_arn

  service_security_group_ids = [
    local.infra.sg_camunda_ports_region_1_id,
    local.infra.sg_package_80_443_region_1_id,
  ]

  environment_variables = concat(
    local.rdbms_env_vars,
    local.opensearch_env_vars_region_1,
    [
      # Only run connectors — disable broker, gateway, operate, tasklist via Spring profile
      {
        name  = "SPRING_PROFILES_ACTIVE"
        value = "connectors"
      },
      # Connectors client configuration
      {
        name  = "CAMUNDA_CLIENT_MODE",
        value = "self-managed"
      },
      {
        name  = "CAMUNDA_CLIENT_RESTADDRESS",
        value = "http://${module.orchestration_cluster_region_1.rest_service_connect}:8080"
      },
      {
        name  = "CAMUNDA_CLIENT_GRPCADDRESS",
        value = "http://${module.orchestration_cluster_region_1.grpc_service_connect}:26500"
      },
      {
        name  = "CAMUNDA_CLIENT_AUTH_METHOD"
        value = "basic"
      },
      {
        name  = "CAMUNDA_CLIENT_AUTH_USERNAME"
        value = "connectors"
      }
    ]
  )

  secrets = [
    {
      name      = "CAMUNDA_CLIENT_AUTH_PASSWORD"
      valueFrom = local.infra.connectors_password_secret_region_1_arn
    }
  ]

  task_desired_count = 1
  extra_task_role_attachments = concat(
    local.infra.rds_db_connect_policy_region_1_arn != null ? [local.infra.rds_db_connect_policy_region_1_arn] : [],
  )
  service_timeouts = {
    create = "30m"
    update = "30m"
    delete = "15m"
  }
}
