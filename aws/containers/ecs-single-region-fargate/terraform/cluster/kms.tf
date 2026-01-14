################################################################
#                        Secrets KMS Key                       #
################################################################

# Secrets Manager encrypts secrets using the AWS managed key by default.
# This stack uses a customer-managed KMS key (CMK) explicitly to enable
# stronger control and auditing (AVD-AWS-0098).

resource "aws_kms_key" "secrets" {
  count = var.secrets_kms_key_arn == "" ? 1 : 0

  description             = "CMK for Secrets Manager secrets (${var.prefix})"
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

resource "aws_kms_alias" "secrets" {
  count = var.secrets_kms_key_arn == "" ? 1 : 0

  name          = "alias/${var.prefix}-secrets"
  target_key_id = aws_kms_key.secrets[0].key_id
}

locals {
  secrets_kms_key_arn_effective = var.secrets_kms_key_arn != "" ? var.secrets_kms_key_arn : aws_kms_key.secrets[0].arn
}
