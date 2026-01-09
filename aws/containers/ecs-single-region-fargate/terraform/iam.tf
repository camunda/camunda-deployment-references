# Centralized IAM Roles for ECS Services - Executioner Role
# Task specific roles are kept as part of the modules

locals {
  # Extract cluster name from cluster ID for IAM policies
  cluster_name = aws_ecs_cluster.ecs.name
}

################################################################
#                    ECS Task Execution Role                   #
################################################################

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.prefix}-ecs-task-execution-role"

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
    Name = "${var.prefix}-ecs-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################################################
#                      ECS Service Role                        #
################################################################

resource "aws_iam_role" "ecs_service" {
  name = "${var.prefix}-ecs-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.prefix}-ecs-service-role"
  }
}

resource "aws_iam_role_policy" "ecs_service" {
  name = "${var.prefix}-ecs-service-policy"
  role = aws_iam_role.ecs_service.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSServiceManagement"
        Effect = "Allow"
        Action = [
          "ecs:CreateService",
          "ecs:DeleteService",
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = [
          "arn:aws:ecs:${data.aws_region.current.id}:*:service/${local.cluster_name}/*"
        ]
      },
      {
        Sid    = "ECSTaskManagement"
        Effect = "Allow"
        Action = [
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RunTask",
          "ecs:StopTask"
        ]
        Resource = [
          "arn:aws:ecs:${data.aws_region.current.id}:*:task/${local.cluster_name}/*",
          "arn:aws:ecs:${data.aws_region.current.id}:*:task-definition/${var.prefix}-*"
        ]
      },
      {
        Sid    = "LoadBalancerManagement"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:Describe*",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:RegisterTargets"
        ]
        Resource = [
          aws_lb.main.arn,
          aws_lb.grpc.arn,
          "arn:aws:elasticloadbalancing:${data.aws_region.current.id}:*:targetgroup/${var.prefix}-*"
        ]
      },
      {
        Sid    = "EC2NetworkInterface"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:vpc" = "arn:aws:ec2:${data.aws_region.current.id}:*:vpc/${module.vpc.vpc_id}"
          }
        }
      },
      {
        Sid    = "EC2DescribeOnly"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################
#                    Registry Credentials Policy               #
################################################################

# Attach registry credentials policy to task execution role if registry is configured
# This applies to all services since they share the same task execution role
resource "aws_iam_role_policy_attachment" "task_execution_registry" {
  count = var.registry_username != "" ? 1 : 0

  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.registry_secrets_policy[0].arn
}

################################################################
#                    ECS Task Secrets Policy                   #
################################################################

locals {
  # Secrets referenced in container definition 'secrets' (valueFrom is typically a Secrets Manager ARN)
  ecs_task_secret_arns = [
    aws_secretsmanager_secret.connectors_client_auth_password.arn,
    aws_secretsmanager_secret.orchestration_admin_user_password.arn,
    aws_secretsmanager_secret.db_admin_password.arn,
  ]
}

resource "aws_iam_policy" "ecs_task_secrets_policy" {
  count = length(local.ecs_task_secret_arns) > 0 ? 1 : 0

  name        = "${var.prefix}-ecs-task-secrets-policy"
  description = "Allow ECS task execution role to read Secrets Manager values used as ECS task secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = local.ecs_task_secret_arns
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = local.secrets_kms_key_arn_effective
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_task_secrets" {
  count = length(local.ecs_task_secret_arns) > 0 ? 1 : 0

  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_task_secrets_policy[0].arn
}

################################################################
#                    RDS IAM Auth Support                      #
################################################################

resource "aws_iam_policy" "rds_db_connect_camunda" {
  name        = "${var.prefix}-rds-db-connect-camunda"
  description = "Allow ECS tasks to connect to Aurora PostgreSQL as the IAM DB user 'camunda'"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRDSDBConnect"
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:dbuser:${module.postgresql.aurora_cluster_resource_id}/camunda"
        ]
      }
    ]
  })
}
