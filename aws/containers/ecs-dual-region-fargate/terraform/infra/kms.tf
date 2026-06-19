################################################################
#                   Secrets KMS Keys (per region)              #
################################################################

data "aws_caller_identity" "current" {}

# Region 0
resource "aws_kms_key" "secrets_region_0" {
  count = var.secrets_kms_key_arn == "" ? 1 : 0

  description             = "CMK for Secrets Manager secrets (${local.prefix_region_0})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "secrets_region_0" {
  count = var.secrets_kms_key_arn == "" ? 1 : 0

  name          = "alias/${local.prefix_region_0}-secrets"
  target_key_id = aws_kms_key.secrets_region_0[0].key_id
}

locals {
  secrets_kms_key_arn_region_0 = var.secrets_kms_key_arn != "" ? var.secrets_kms_key_arn : aws_kms_key.secrets_region_0[0].arn
}

# Region 1
resource "aws_kms_key" "secrets_region_1" {
  provider = aws.accepter
  count    = var.secrets_kms_key_arn_accepter == "" ? 1 : 0

  description             = "CMK for Secrets Manager secrets (${local.prefix_region_1})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "secrets_region_1" {
  provider = aws.accepter
  count    = var.secrets_kms_key_arn_accepter == "" ? 1 : 0

  name          = "alias/${local.prefix_region_1}-secrets"
  target_key_id = aws_kms_key.secrets_region_1[0].key_id
}

locals {
  secrets_kms_key_arn_region_1 = var.secrets_kms_key_arn_accepter != "" ? var.secrets_kms_key_arn_accepter : aws_kms_key.secrets_region_1[0].arn
}

################################################################
#                    S3 KMS Keys (per region)                  #
################################################################

resource "aws_kms_key" "s3_region_0" {
  description             = "KMS key for ${local.prefix_region_0} S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${local.prefix_region_0}-s3-kms-key"
  }
}

resource "aws_kms_alias" "s3_region_0" {
  name          = "alias/${local.prefix_region_0}-s3-key"
  target_key_id = aws_kms_key.s3_region_0.key_id
}

resource "aws_kms_key" "s3_region_1" {
  provider = aws.accepter

  description             = "KMS key for ${local.prefix_region_1} S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${local.prefix_region_1}-s3-kms-key"
  }
}

resource "aws_kms_alias" "s3_region_1" {
  provider = aws.accepter

  name          = "alias/${local.prefix_region_1}-s3-key"
  target_key_id = aws_kms_key.s3_region_1.key_id
}
