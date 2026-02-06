data "aws_region" "current" {}

module "orchestration_cluster" {
  source = "../../../../modules/ecs/fargate/orchestration-cluster"

  depends_on = [null_resource.run_db_seed_task]

  prefix              = "${var.prefix}-oc1"
  ecs_cluster_id      = aws_ecs_cluster.ecs.id
  vpc_id              = module.vpc.vpc_id
  vpc_private_subnets = module.vpc.private_subnets
  aws_region          = data.aws_region.current.region

  # IAM Roles (execution role centrally managed, task role module-specific)
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn

  # Load Balancer configuration
  alb_listener_http_webapp_arn     = aws_lb_listener.http_webapp.arn
  alb_listener_http_management_arn = aws_lb_listener.http_management.arn
  nlb_arn                          = aws_lb.grpc.arn

  enable_alb_http_webapp_listener_rule = true
  # management endpoint is unprotected, only enable if you know what you are doing.
  # Consider secure access alternatives via temporary jump host / VPN connected to VPC / lambda or step functions.
  enable_alb_http_management_listener_rule = false
  enable_nlb_grpc_26500_listener           = true

  environment_variables = [
    {
      name  = "CAMUNDA_CLUSTER_REPLICATIONFACTOR"
      value = "3"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONCOUNT"
      value = "3"
    },
    # Secondary Storage - RDBMS (Aurora PostgreSQL with IAM Auth)
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
      value = "jdbc:aws-wrapper:postgresql://${module.postgresql.aurora_endpoint}:5432/${var.db_name}?wrapperPlugins=iam"
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
    # Embedded Identity
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
      value = aws_s3_bucket.backup.bucket
    },
    {
      name  = "CAMUNDA_DATA_BACKUP_REPOSITORYNAME"
      value = aws_s3_bucket.backup.bucket
    },
  ]

  # Prefer ECS task secrets for sensitive values (container definition 'secrets')
  secrets = [
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD"
      valueFrom = aws_secretsmanager_secret.orchestration_admin_user_password.arn
    },
    {
      name      = "CAMUNDA_SECURITY_INITIALIZATION_USERS_1_PASSWORD"
      valueFrom = aws_secretsmanager_secret.connectors_client_auth_password.arn
    }
  ]

  registry_credentials_arn = join("", aws_secretsmanager_secret.registry_credentials[*].arn)

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
    aws_security_group.efs.id,
  ]
  efs_security_group_ids = [aws_security_group.efs.id]

  task_desired_count = 3

  # Pass additional policies to orchestration cluster task role
  extra_task_role_attachments = [
    aws_iam_policy.rds_db_connect_camunda.arn,
    aws_iam_policy.s3_backup_access_policy.arn,
  ]

}

module "connectors" {
  source = "../../../../modules/ecs/fargate/connectors"

  prefix                               = "${var.prefix}-oc1"
  ecs_cluster_id                       = aws_ecs_cluster.ecs.id
  vpc_id                               = module.vpc.vpc_id
  vpc_private_subnets                  = module.vpc.private_subnets
  aws_region                           = data.aws_region.current.region
  s2s_cloudmap_namespace               = module.orchestration_cluster.s2s_cloudmap_namespace
  alb_listener_http_webapp_arn         = aws_lb_listener.http_webapp.arn
  enable_alb_http_webapp_listener_rule = true
  log_group_name                       = module.orchestration_cluster.log_group_name

  # IAM Roles (execution role centrally managed, task role module-specific)
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn

  registry_credentials_arn = join("", aws_secretsmanager_secret.registry_credentials[*].arn)

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
  ]

  environment_variables = [
    # Self-managed connection to orchestration cluster (basic auth)
    {
      name  = "CAMUNDA_CLIENT_MODE",
      value = "self-managed"
    },
    {
      name  = "CAMUNDA_CLIENT_RESTADDRESS",
      value = "http://${module.orchestration_cluster.rest_service_connect}:8080"
    },
    {
      name  = "CAMUNDA_CLIENT_GRPCADDRESS",
      value = "http://${module.orchestration_cluster.grpc_service_connect}:26500"
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

  # Prefer ECS task secrets for sensitive values (container definition 'secrets')
  secrets = [
    {
      name      = "CAMUNDA_CLIENT_AUTH_PASSWORD"
      valueFrom = aws_secretsmanager_secret.connectors_client_auth_password.arn
    }
  ]

  task_desired_count = 1

  # Pass additional policies to connectors task role
  extra_task_role_attachments = []

}
