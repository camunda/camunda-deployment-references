# S3 bucket
# trivy:ignore:AVD-AWS-0089 S3 bucket logging ignored for this use case, but can be enabled by customers themselves if needed
# trivy:ignore:AVD-AWS-0090 S3 bucket versioning ignored for this use case as the metadata changes cause excessive versioning with no benefit
resource "aws_s3_bucket" "main" {
  bucket        = "${var.prefix}-bucket"
  force_destroy = var.s3_force_destroy
}

# KMS key for S3 bucket encryption
#
# Explicit key policy is required. Without it Terraform relies on the AWS API default, which
# enables IAM delegation only when the key is created through the console. Keys created via API
# (as Terraform does) may not include the "Enable IAM User Permissions" root statement, which
# means identity-based policies on the task role cannot allow kms:Decrypt on this key.
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "s3" {
  description             = "KMS key for ${var.prefix} S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  # Delegate access control to IAM — without this statement, IAM policies on the task role
  # cannot grant kms:Decrypt even if they list the key ARN explicitly.
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

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.prefix}-s3-encryption"
  target_key_id = aws_kms_key.s3.key_id
}

# Enable server-side encryption with customer managed KMS key
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM policy for S3 bucket access - attached to ECS task role
resource "aws_iam_policy" "s3_access" {
  name = "${var.prefix}-s3-access-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.main.arn
      },
      {
        Sid    = "AllowS3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.main.arn}/*"
      },
      {
        Sid    = "AllowKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.s3.arn
      }
    ]
  })
}
