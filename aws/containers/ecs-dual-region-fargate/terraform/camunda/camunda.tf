################################################################
#         Orchestration Cluster - Region 0 (owner)             #
################################################################

module "orchestration_cluster_region_0" {
  source = "../../../../modules/ecs/fargate/orchestration-cluster"

  depends_on = [null_resource.run_db_seed_task]

  prefix              = "${local.prefix_region_0}-oc"
  s3_force_destroy    = var.s3_force_destroy
  ecs_cluster_id      = local.infra.region_0_ecs_cluster_id
  vpc_id              = local.infra.region_0_vpc_id
  vpc_private_subnets = local.infra.region_0_private_subnets
  aws_region          = data.aws_region.region_0.id

  # IAM Roles
  ecs_task_execution_role_arn = local.infra.region_0_ecs_task_execution_role_arn

  # Load Balancer configuration
  alb_listener_http_webapp_arn     = local.infra.region_0_alb_http_webapp_listener_arn
  alb_listener_http_management_arn = local.infra.region_0_alb_http_management_listener_arn
  nlb_arn                          = local.infra.region_0_nlb_grpc_arn

  enable_alb_http_webapp_listener_rule     = true
  enable_alb_http_management_listener_rule = false
  enable_nlb_grpc_26500_listener           = true

  # Image
  image                    = "registry.camunda.cloud/team-zeebe/camunda:c8-ecs-multi-region-b70a4759"
  registry_credentials_arn = var.registry_username != "" ? aws_secretsmanager_secret.registry_credentials_region_0[0].arn : ""

  # Dual-region cluster configuration
  task_desired_count            = local.brokers_per_region
  cluster_size                  = local.cluster_size
  replication_factor            = local.replication_factor
  partition_count               = local.partition_count
  region_id                     = 0
  initial_contact_points        = "orchestration-cluster-sc:26502,${local.infra.region_1_nlb_raft_dns_name}:26502"
  internal_nlb_arn              = local.infra.region_0_nlb_raft_arn
  enable_internal_nlb_raft_listener = true

  # Increase health check grace periods for cross-region Raft formation.
  # Zeebe brokers wait for all 8 members before partitions become active,
  # which can take 5-15 min across two regions.
  service_health_check_grace_period_seconds   = 1200
  container_health_check_start_period_seconds = 300

  # Zeebe's /actuator/health/readiness only passes when all 8 brokers across
  # both regions have formed Raft quorum. With wait_for_steady_state=true
  # (the module default), Terraform would block on region 0 indefinitely
  # because region 0 brokers can never be healthy until region 1 is also up.
  # Setting false lets both regions deploy in parallel; verify convergence
  # via the readiness endpoint after apply completes.
  wait_for_steady_state = false

  environment_variables = [
    # Secondary Storage - RDBMS (Aurora PostgreSQL Global DB with IAM Auth + Failover)
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_AUTOCONFIGURECAMUNDAEXPORTER"
      value = "false"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "rdbms"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_URL"
      value = local.aurora_jdbc_url
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_USERNAME"
      value = "camunda"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_AUTODDL"
      value = "true"
    },
    {
      name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
      value = "software.amazon.jdbc.Driver"
    },
    # Admin
    ## Admin user
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_USERNAME"
      value = "admin"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_NAME"
      value = "Admin User"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_EMAIL"
      value = "admin@example.com"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0"
      value = "admin"
    },
    ## Connectors user
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_USERNAME"
      value = "connectors"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_NAME"
      value = "Connectors User"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_EMAIL"
      value = "connectors@example.com"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_CONNECTORS_USERS_0"
      value = "connectors"
    },
    # Backup / Restore configuration
    {
      name  = "CAMUNDA_DATA_BACKUP_STORE"
      value = "S3"
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_S3_BUCKETNAME"
      value = local.infra.region_0_backup_bucket_name
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
      value = local.infra.region_0_backup_bucket_name
    },
    # Cluster identification
    {
      name  = "CAMUNDA_CLUSTER_NAME"
      value = "yes-r1-oc-orchestration-cluster"
    },
    {
      name  = "CAMUNDA_CLUSTER_REGION"
      value = "eu-west-1"
    },
    # Region-aware partitioning
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_SCHEME"
      value = "REGION_AWARE"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_NAME"
      value = "eu-west-1"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_NUMBEROFREPLICAS"
      value = "2"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_NUMBEROFBROKERS"
      value = "2"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_PRIORITY"
      value = "1000"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_NAME"
      value = "eu-west-3"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_NUMBEROFREPLICAS"
      value = "2"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_NUMBEROFBROKERS"
      value = "2"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_PRIORITY"
      value = "500"
    },
    {
      name  = "CAMUNDA_CLUSTER_INITIALCONTACTPOINTS"
      value = "orchestration-cluster-sc:26502,${local.infra.region_1_nlb_raft_dns_name}:26502"
    },
  ]

  secrets = [
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD"
      valueFrom = aws_secretsmanager_secret.admin_user_password_region_0.arn
    },
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_PASSWORD"
      valueFrom = aws_secretsmanager_secret.connectors_password_region_0.arn
    }
  ]

  service_security_group_ids = [
    local.infra.region_0_camunda_ports_sg_id,
    local.infra.region_0_package_80_443_sg_id,
    local.infra.region_0_efs_sg_id,
  ]
  efs_security_group_ids = [local.infra.region_0_efs_sg_id]

  extra_task_role_attachments = [
    local.infra.region_0_rds_db_connect_policy_arn,
    local.infra.region_0_s3_backup_access_policy_arn,
  ]
}

################################################################
#        Orchestration Cluster - Region 1 (accepter)           #
################################################################

module "orchestration_cluster_region_1" {
  source = "../../../../modules/ecs/fargate/orchestration-cluster"

  providers = {
    aws = aws.accepter
  }

  depends_on = [null_resource.run_db_seed_task]

  prefix              = "${local.prefix_region_1}-oc"
  s3_force_destroy    = var.s3_force_destroy
  ecs_cluster_id      = local.infra.region_1_ecs_cluster_id
  vpc_id              = local.infra.region_1_vpc_id
  vpc_private_subnets = local.infra.region_1_private_subnets
  aws_region          = data.aws_region.region_1.id

  # IAM Roles
  ecs_task_execution_role_arn = local.infra.region_1_ecs_task_execution_role_arn

  # Load Balancer configuration
  alb_listener_http_webapp_arn     = local.infra.region_1_alb_http_webapp_listener_arn
  alb_listener_http_management_arn = local.infra.region_1_alb_http_management_listener_arn
  nlb_arn                          = local.infra.region_1_nlb_grpc_arn

  enable_alb_http_webapp_listener_rule     = true
  enable_alb_http_management_listener_rule = false
  enable_nlb_grpc_26500_listener           = true

  # Image
  image                    = "registry.camunda.cloud/team-zeebe/camunda:c8-ecs-multi-region-b70a4759"
  registry_credentials_arn = var.registry_username != "" ? aws_secretsmanager_secret.registry_credentials_region_1[0].arn : ""

  # Dual-region cluster configuration
  task_desired_count            = local.brokers_per_region
  cluster_size                  = local.cluster_size
  replication_factor            = local.replication_factor
  partition_count               = local.partition_count
  region_id                     = 1
  initial_contact_points        = "orchestration-cluster-sc:26502,${local.infra.region_0_nlb_raft_dns_name}:26502"
  internal_nlb_arn              = local.infra.region_1_nlb_raft_arn
  enable_internal_nlb_raft_listener = true

  # Increase health check grace periods for cross-region Raft formation.
  # Zeebe brokers wait for all 8 members before partitions become active,
  # which can take 5-15 min across two regions.
  service_health_check_grace_period_seconds   = 1200
  container_health_check_start_period_seconds = 300

  # See region 0 comment above — same reasoning applies.
  wait_for_steady_state = false

  environment_variables = [
    # Secondary Storage - RDBMS (Aurora PostgreSQL Global DB with IAM Auth + Failover)
    # Both regions point to the same Aurora Global DB writer endpoint.
    # The AWS JDBC Wrapper with failover plugin handles writer redirection after Global DB failover.
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_AUTOCONFIGURECAMUNDAEXPORTER"
      value = "false"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "rdbms"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_URL"
      value = local.aurora_jdbc_url
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_USERNAME"
      value = "camunda"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_AUTODDL"
      value = "true"
    },
    {
      name  = "SPRING_DATASOURCE_DRIVER_CLASS_NAME"
      value = "software.amazon.jdbc.Driver"
    },
    # Admin
    ## Admin user
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_USERNAME"
      value = "admin"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_NAME"
      value = "Admin User"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_EMAIL"
      value = "admin@example.com"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0"
      value = "admin"
    },
    ## Connectors user
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_USERNAME"
      value = "connectors"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_NAME"
      value = "Connectors User"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_EMAIL"
      value = "connectors@example.com"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_CONNECTORS_USERS_0"
      value = "connectors"
    },
    # Backup / Restore configuration
    {
      name  = "CAMUNDA_DATA_BACKUP_STORE"
      value = "S3"
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_S3_BUCKETNAME"
      value = local.infra.region_1_backup_bucket_name
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
      value = local.infra.region_1_backup_bucket_name
    },
    # Cluster identification
    {
      name  = "CAMUNDA_CLUSTER_NAME"
      value = "yes-r1-oc-orchestration-cluster"
    },
    {
      name  = "CAMUNDA_CLUSTER_REGION"
      value = "eu-west-3"
    },
    # Region-aware partitioning
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_SCHEME"
      value = "REGION_AWARE"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_NAME"
      value = "eu-west-1"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_NUMBEROFREPLICAS"
      value = "2"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_NUMBEROFBROKERS"
      value = "2"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_0_PRIORITY"
      value = "1000"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_NAME"
      value = "eu-west-3"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_NUMBEROFREPLICAS"
      value = "2"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_NUMBEROFBROKERS"
      value = "2"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONING_REGIONAWARE_REGIONS_1_PRIORITY"
      value = "500"
    },
    {
      name  = "CAMUNDA_CLUSTER_INITIALCONTACTPOINTS"
      value = "orchestration-cluster-sc:26502,${local.infra.region_0_nlb_raft_dns_name}:26502"
    },
  ]

  secrets = [
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD"
      valueFrom = aws_secretsmanager_secret.admin_user_password_region_1.arn
    },
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_PASSWORD"
      valueFrom = aws_secretsmanager_secret.connectors_password_region_1.arn
    }
  ]

  service_security_group_ids = [
    local.infra.region_1_camunda_ports_sg_id,
    local.infra.region_1_package_80_443_sg_id,
    local.infra.region_1_efs_sg_id,
  ]
  efs_security_group_ids = [local.infra.region_1_efs_sg_id]

  extra_task_role_attachments = [
    local.infra.region_1_rds_db_connect_policy_arn,
    local.infra.region_1_s3_backup_access_policy_arn,
  ]
}

################################################################
#              Connectors - Region 0 (owner)                   #
################################################################

module "connectors_region_0" {
  source = "../../../../modules/ecs/fargate/connectors"

  prefix                               = "${local.prefix_region_0}-oc"
  ecs_cluster_id                       = local.infra.region_0_ecs_cluster_id
  vpc_id                               = local.infra.region_0_vpc_id
  vpc_private_subnets                  = local.infra.region_0_private_subnets
  aws_region                           = data.aws_region.region_0.id
  s2s_cloudmap_namespace               = module.orchestration_cluster_region_0.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = local.infra.region_0_alb_http_webapp_listener_arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster_region_0.log_group_name

  ecs_task_execution_role_arn = local.infra.region_0_ecs_task_execution_role_arn

  service_security_group_ids = [
    local.infra.region_0_camunda_ports_sg_id,
    local.infra.region_0_package_80_443_sg_id,
  ]

  environment_variables = [
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

  secrets = [
    {
      name      = "CAMUNDA_CLIENT_AUTH_PASSWORD"
      valueFrom = aws_secretsmanager_secret.connectors_password_region_0.arn
    }
  ]

  task_desired_count          = 1
  wait_for_steady_state       = false
  extra_task_role_attachments = []
}

################################################################
#             Connectors - Region 1 (accepter)                 #
################################################################

module "connectors_region_1" {
  source = "../../../../modules/ecs/fargate/connectors"

  providers = {
    aws = aws.accepter
  }

  prefix                               = "${local.prefix_region_1}-oc"
  ecs_cluster_id                       = local.infra.region_1_ecs_cluster_id
  vpc_id                               = local.infra.region_1_vpc_id
  vpc_private_subnets                  = local.infra.region_1_private_subnets
  aws_region                           = data.aws_region.region_1.id
  s2s_cloudmap_namespace               = module.orchestration_cluster_region_1.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = local.infra.region_1_alb_http_webapp_listener_arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster_region_1.log_group_name

  ecs_task_execution_role_arn = local.infra.region_1_ecs_task_execution_role_arn

  service_security_group_ids = [
    local.infra.region_1_camunda_ports_sg_id,
    local.infra.region_1_package_80_443_sg_id,
  ]

  environment_variables = [
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

  secrets = [
    {
      name      = "CAMUNDA_CLIENT_AUTH_PASSWORD"
      valueFrom = aws_secretsmanager_secret.connectors_password_region_1.arn
    }
  ]

  task_desired_count          = 1
  wait_for_steady_state       = false
  extra_task_role_attachments = []
}
