# Compute layer: the ECS cluster and what every service shares: the task execution role,
# the security groups, the registry credentials and the key that encrypts the secrets.
# Later layers that create secrets attach their own read policy to the execution role
# (see task_execution_role_name).

data "aws_caller_identity" "current" {}

resource "aws_ecs_cluster" "this" {
  name = "${var.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

################################################################
#                      Secrets KMS key                         #
################################################################

resource "aws_kms_key" "secrets" {
  count = var.secrets_kms_key_arn == "" ? 1 : 0

  description             = "CMK for Secrets Manager secrets (${var.prefix})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMUserPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "secrets" {
  count = var.secrets_kms_key_arn == "" ? 1 : 0

  name          = "alias/${var.prefix}-secrets"
  target_key_id = aws_kms_key.secrets[0].key_id
}

locals {
  secrets_kms_key_arn = var.secrets_kms_key_arn != "" ? var.secrets_kms_key_arn : aws_kms_key.secrets[0].arn
}

################################################################
#                  Task execution role                         #
################################################################

resource "aws_iam_role" "task_execution" {
  name = "${var.prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################################################
#                  Registry credentials                        #
################################################################

resource "aws_secretsmanager_secret" "registry_credentials" {
  count = var.registry_username != "" ? 1 : 0

  name                    = "${var.prefix}-registry-credentials"
  description             = "Registry credentials for ECS to pull images"
  recovery_window_in_days = 0
  kms_key_id              = local.secrets_kms_key_arn
}

resource "aws_secretsmanager_secret_version" "registry_credentials" {
  count = var.registry_username != "" ? 1 : 0

  secret_id = aws_secretsmanager_secret.registry_credentials[0].id
  secret_string = jsonencode({
    username = var.registry_username
    password = var.registry_password
  })
}

resource "aws_iam_policy" "registry_secrets" {
  count = var.registry_username != "" ? 1 : 0

  name = "${var.prefix}-registry-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.registry_credentials[0].arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = local.secrets_kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "registry_secrets" {
  count = var.registry_username != "" ? 1 : 0

  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.registry_secrets[0].arn
}

################################################################
#                      Security groups                         #
################################################################

locals {
  # The VPC itself, plus the VPCs of other regions once the deployment grows.
  peer_cidr_blocks = concat([var.vpc_cidr], var.additional_cidr_blocks)
}

# Shared by every service: the Camunda ports inside the VPC (and the peered ones), and NFS to EFS.
resource "aws_security_group" "camunda_ports_within_vpc" {
  name        = "${var.prefix}-allow-necessary-camunda-ports-within-vpc"
  description = "Allow necessary Camunda ports within the VPC"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "TCP"
      cidr_blocks = local.peer_cidr_blocks
      description = "Allow inbound traffic on port ${ingress.value}"
    }
  }

  dynamic "egress" {
    for_each = var.ports
    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "TCP"
      cidr_blocks = local.peer_cidr_blocks
      description = "Allow outbound traffic on port ${egress.value}"
    }
  }

  egress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "TCP"
    security_groups = [aws_security_group.efs.id]
    description     = "Allow NFS traffic to EFS"
  }
}

# Outbound HTTP(S): image pulls, Secrets Manager, AWS APIs through the NAT gateway.
resource "aws_security_group" "egress_80_443" {
  name        = "${var.prefix}-allow-package-80-443"
  description = "Allow outbound HTTP and HTTPS traffic for image pulls and AWS APIs"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound HTTP traffic"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound HTTPS traffic"
  }
}

resource "aws_security_group" "efs" {
  name        = "${var.prefix}-efs"
  description = "Security group for EFS"
  vpc_id      = var.vpc_id

  ingress {
    description = "nfs from ECS tasks"
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "nfs outbound"
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    cidr_blocks = [var.vpc_cidr]
  }
}
