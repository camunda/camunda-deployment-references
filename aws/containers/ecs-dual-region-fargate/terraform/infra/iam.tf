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

# RDS IAM auth for region 0 tasks
resource "aws_iam_policy" "rds_db_connect_region_0" {
  name        = "${local.prefix_region_0}-rds-db-connect-camunda"
  description = "Allow ECS tasks to connect to Aurora PostgreSQL as IAM DB user 'camunda'"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRDSDBConnect"
        Effect = "Allow"
        Action = ["rds-db:connect"]
        Resource = [
          "arn:aws:rds-db:${data.aws_region.region_0.id}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora_global.primary_cluster_resource_id}/camunda",
          "arn:aws:rds-db:${data.aws_region.region_1.id}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora_global.secondary_cluster_resource_id}/camunda",
        ]
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

# RDS IAM auth for region 1 tasks (same policy as region 0 — both regions connect to Global DB)
resource "aws_iam_policy" "rds_db_connect_region_1" {
  provider = aws.accepter

  name        = "${local.prefix_region_1}-rds-db-connect-camunda"
  description = "Allow ECS tasks to connect to Aurora PostgreSQL as IAM DB user 'camunda'"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRDSDBConnect"
        Effect = "Allow"
        Action = ["rds-db:connect"]
        Resource = [
          "arn:aws:rds-db:${data.aws_region.region_0.id}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora_global.primary_cluster_resource_id}/camunda",
          "arn:aws:rds-db:${data.aws_region.region_1.id}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora_global.secondary_cluster_resource_id}/camunda",
        ]
      }
    ]
  })
}
