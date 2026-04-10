################################################################
#         Orchestration Cluster - Region 0 (owner)             #
################################################################

module "orchestration_cluster_region_0" {
  source = "../../../../modules/ecs/fargate/orchestration-cluster"

  depends_on = [null_resource.run_db_seed_task]

  prefix              = "${local.prefix_region_0}-oc"
  ecs_cluster_id      = aws_ecs_cluster.region_0.id
  vpc_id              = module.vpc_region_0.vpc_id
  vpc_private_subnets = module.vpc_region_0.private_subnets
  aws_region          = data.aws_region.region_0.name

  # IAM Roles
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution_region_0.arn

  # Load Balancer configuration
  alb_listener_http_webapp_arn     = aws_lb_listener.http_webapp_region_0.arn
  alb_listener_http_management_arn = aws_lb_listener.http_management_region_0.arn
  nlb_arn                          = aws_lb.nlb_grpc_region_0.arn

  enable_alb_http_webapp_listener_rule     = true
  enable_alb_http_management_listener_rule = false
  enable_nlb_grpc_26500_listener           = true

  # Dual-region cluster configuration
  task_desired_count     = local.brokers_per_region
  cluster_size           = local.cluster_size
  replication_factor     = local.replication_factor
  partition_count        = local.partition_count
  region_id              = 0
  initial_contact_points = "orchestration-cluster-sc:26502,${aws_lb.nlb_raft_region_1.dns_name}:26502"
  internal_nlb_arn       = aws_lb.nlb_raft_region_0.arn

  # Increase health check grace period for cross-region Raft formation
  service_health_check_grace_period_seconds = 1200

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
      value = "jdbc:aws-wrapper:postgresql://${module.aurora_global.primary_cluster_endpoint}:5432/${var.db_name}?wrapperPlugins=iam,failover"
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
      value = aws_s3_bucket.backup_region_0.bucket
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
      value = aws_s3_bucket.backup_region_0.bucket
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
    aws_security_group.camunda_ports_region_0.id,
    aws_security_group.package_80_443_region_0.id,
    aws_security_group.efs_region_0.id,
  ]
  efs_security_group_ids = [aws_security_group.efs_region_0.id]

  extra_task_role_attachments = [
    aws_iam_policy.rds_db_connect_region_0.arn,
    aws_iam_policy.s3_backup_access_region_0.arn,
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
  ecs_cluster_id      = aws_ecs_cluster.region_1.id
  vpc_id              = module.vpc_region_1.vpc_id
  vpc_private_subnets = module.vpc_region_1.private_subnets
  aws_region          = data.aws_region.region_1.name

  # IAM Roles
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution_region_1.arn

  # Load Balancer configuration
  alb_listener_http_webapp_arn     = aws_lb_listener.http_webapp_region_1.arn
  alb_listener_http_management_arn = aws_lb_listener.http_management_region_1.arn
  nlb_arn                          = aws_lb.nlb_grpc_region_1.arn

  enable_alb_http_webapp_listener_rule     = true
  enable_alb_http_management_listener_rule = false
  enable_nlb_grpc_26500_listener           = true

  # Dual-region cluster configuration
  task_desired_count     = local.brokers_per_region
  cluster_size           = local.cluster_size
  replication_factor     = local.replication_factor
  partition_count        = local.partition_count
  region_id              = 1
  initial_contact_points = "orchestration-cluster-sc:26502,${aws_lb.nlb_raft_region_0.dns_name}:26502"
  internal_nlb_arn       = aws_lb.nlb_raft_region_1.arn

  # Increase health check grace period for cross-region Raft formation
  service_health_check_grace_period_seconds = 1200

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
      value = "jdbc:aws-wrapper:postgresql://${module.aurora_global.primary_cluster_endpoint}:5432/${var.db_name}?wrapperPlugins=iam,failover"
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
      value = aws_s3_bucket.backup_region_1.bucket
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
      value = aws_s3_bucket.backup_region_1.bucket
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
    aws_security_group.camunda_ports_region_1.id,
    aws_security_group.package_80_443_region_1.id,
    aws_security_group.efs_region_1.id,
  ]
  efs_security_group_ids = [aws_security_group.efs_region_1.id]

  extra_task_role_attachments = [
    aws_iam_policy.rds_db_connect_region_1.arn,
    aws_iam_policy.s3_backup_access_region_1.arn,
  ]
}

################################################################
#              Connectors - Region 0 (owner)                   #
################################################################

module "connectors_region_0" {
  source = "../../../../modules/ecs/fargate/connectors"

  prefix                               = "${local.prefix_region_0}-oc"
  ecs_cluster_id                       = aws_ecs_cluster.region_0.id
  vpc_id                               = module.vpc_region_0.vpc_id
  vpc_private_subnets                  = module.vpc_region_0.private_subnets
  aws_region                           = data.aws_region.region_0.name
  s2s_cloudmap_namespace               = module.orchestration_cluster_region_0.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = aws_lb_listener.http_webapp_region_0.arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster_region_0.log_group_name

  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution_region_0.arn

  service_security_group_ids = [
    aws_security_group.camunda_ports_region_0.id,
    aws_security_group.package_80_443_region_0.id,
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
  ecs_cluster_id                       = aws_ecs_cluster.region_1.id
  vpc_id                               = module.vpc_region_1.vpc_id
  vpc_private_subnets                  = module.vpc_region_1.private_subnets
  aws_region                           = data.aws_region.region_1.name
  s2s_cloudmap_namespace               = module.orchestration_cluster_region_1.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = aws_lb_listener.http_webapp_region_1.arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster_region_1.log_group_name

  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution_region_1.arn

  service_security_group_ids = [
    aws_security_group.camunda_ports_region_1.id,
    aws_security_group.package_80_443_region_1.id,
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
  extra_task_role_attachments = []
}
