################################################################
#              Region 0 IAM Roles                              #
################################################################

data "aws_region" "region_0" {}

data "aws_region" "region_1" {
  provider = aws.accepter
}

# ECS Task Execution Role (region 0)
resource "aws_iam_role" "ecs_task_execution_region_0" {
  name = "${local.prefix_region_0}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.prefix_region_0}-ecs-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_region_0" {
  role       = aws_iam_role.ecs_task_execution_region_0.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets access for task execution (region 0)
resource "aws_iam_policy" "ecs_task_secrets_region_0" {
  name        = "${local.prefix_region_0}-ecs-task-secrets"
  description = "Allow ECS task execution role to read Secrets Manager values"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = concat(
          [
            aws_secretsmanager_secret.admin_user_password_region_0.arn,
            aws_secretsmanager_secret.connectors_password_region_0.arn,
          ],
          var.secondary_storage_type == "rdbms" ? [aws_secretsmanager_secret.db_admin_password_region_0.arn] : [],
          var.registry_username != "" ? [aws_secretsmanager_secret.registry_credentials_region_0[0].arn] : [],
        )
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [local.secrets_kms_key_arn_region_0]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_secrets_region_0" {
  role       = aws_iam_role.ecs_task_execution_region_0.name
  policy_arn = aws_iam_policy.ecs_task_secrets_region_0.arn
}

# RDS IAM auth for region 0 tasks
resource "aws_iam_policy" "rds_db_connect_region_0" {
  count = var.secondary_storage_type == "rdbms" ? 1 : 0

  name        = "${local.prefix_region_0}-rds-db-connect-camunda"
  description = "Allow ECS tasks to connect to Aurora as IAM DB user 'camunda'"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRDSDBConnect"
        Effect = "Allow"
        Action = ["rds-db:connect"]
        Resource = [
          "arn:aws:rds-db:${data.aws_region.region_0.region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora_global[0].primary_cluster_resource_id}/camunda",
          "arn:aws:rds-db:${data.aws_region.region_1.region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora_global[0].secondary_cluster_resource_id}/camunda",
        ]
      },
      {
        Sid      = "AllowDescribeGlobalCluster"
        Effect   = "Allow"
        Action   = ["rds:DescribeGlobalClusters"]
        Resource = [module.aurora_global[0].global_cluster_arn]
      }
    ]
  })
}

################################################################
#              Region 1 IAM Roles                              #
################################################################

# ECS Task Execution Role (region 1)
resource "aws_iam_role" "ecs_task_execution_region_1" {
  provider = aws.accepter

  name = "${local.prefix_region_1}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.prefix_region_1}-ecs-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_region_1" {
  provider = aws.accepter

  role       = aws_iam_role.ecs_task_execution_region_1.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets access for task execution (region 1)
resource "aws_iam_policy" "ecs_task_secrets_region_1" {
  provider = aws.accepter

  name        = "${local.prefix_region_1}-ecs-task-secrets"
  description = "Allow ECS task execution role to read Secrets Manager values"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = concat(
          [
            aws_secretsmanager_secret.admin_user_password_region_1.arn,
            aws_secretsmanager_secret.connectors_password_region_1.arn,
          ],
          var.registry_username != "" ? [aws_secretsmanager_secret.registry_credentials_region_1[0].arn] : [],
        )
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [local.secrets_kms_key_arn_region_1]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_secrets_region_1" {
  provider = aws.accepter

  role       = aws_iam_role.ecs_task_execution_region_1.name
  policy_arn = aws_iam_policy.ecs_task_secrets_region_1.arn
}

# RDS IAM auth for region 1 tasks (same policy as region 0 — both regions connect to Global DB)
resource "aws_iam_policy" "rds_db_connect_region_1" {
  count    = var.secondary_storage_type == "rdbms" ? 1 : 0
  provider = aws.accepter

  name        = "${local.prefix_region_1}-rds-db-connect-camunda"
  description = "Allow ECS tasks to connect to Aurora as IAM DB user 'camunda'"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRDSDBConnect"
        Effect = "Allow"
        Action = ["rds-db:connect"]
        Resource = [
          "arn:aws:rds-db:${data.aws_region.region_0.region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora_global[0].primary_cluster_resource_id}/camunda",
          "arn:aws:rds-db:${data.aws_region.region_1.region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora_global[0].secondary_cluster_resource_id}/camunda",
        ]
      },
      {
        Sid      = "AllowDescribeGlobalCluster"
        Effect   = "Allow"
        Action   = ["rds:DescribeGlobalClusters"]
        Resource = [module.aurora_global[0].global_cluster_arn]
      }
    ]
  })
}
