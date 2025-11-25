data "aws_region" "current" {}

module "orchestration_cluster" {
  source = "../../../modules/ecs/fargate/orchestration-cluster"

  prefix              = "${var.prefix}-oc1"
  ecs_cluster_id      = aws_ecs_cluster.ecs.id
  vpc_id              = module.vpc.vpc_id
  vpc_private_subnets = module.vpc.private_subnets
  aws_region          = data.aws_region.current.region

  alb_arn = aws_lb.main.arn
  nlb_arn = aws_lb.grpc.arn

  environment_variables = [
    {
      name  = "CAMUNDA_CLUSTER_REPLICATIONFACTOR"
      value = "1"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONCOUNT"
      value = "5"
    },
    # Debug for now
    {
      name  = "ZEEBE_BROKER_DATA_DIRECTORY" # TODO: no fucking clue
      value = "/usr/local/camunda/data"
    },
    {
      name  = "SPRING_LIFECYCLE_TIMEOUTPERSHUTDOWNPHASE" # TODO: no fucking clue
      value = "5s"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "none"
    },
    {
      name  = "CAMUNDA_REST_QUERY_ENABLED"
      value = "false"
    },
    {
      name  = "CAMUNDA_PERSISTENT_SESSIONS_ENABLED"
      value = "false"
    },
    {
      name  = "CAMUNDA_DATABASE_SCHEMA_MANAGER_CREATE_SCHEMA"
      value = "false"
    },
    {
      name  = "SPRING_PROFILES_ACTIVE"
      value = "broker,standalone"
    },
    {
      name  = "CAMUNDA_SECURITY_AUTHENTICATION_METHOD"
      value = "basic"
    },
    {
      name  = "CAMUNDA_SECURITY_AUTHENTICATION_UNPROTECTEDAPI"
      value = "true"
    },
    {
      name  = "CAMUNDA_SECURITY_AUTHORIZATIONS_ENABLED"
      value = "false"
    },
    # Demo user
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_USERNAME"
      value = "demo"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_PASSWORD"
      value = "demo"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_NAME"
      value = "Demo User"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_USERS_0_EMAIL"
      value = "demo@demo.com"
    },
    {
      name  = "CAMUNDA_SECURITY_INITIALIZATION_DEFAULTROLES_ADMIN_USERS_0"
      value = "demo"
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

  extra_service_role_attachments = var.registry_username != "" ? [
    aws_iam_policy.registry_secrets_policy[0].arn
  ] : []

}
