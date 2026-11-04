locals {
  # Lease objects change on every renewal: versioning would only pile up versions.
  versioning_enabled = var.purpose == "backup"
  create_kms_key     = var.kms_key_arn == ""
  kms_key_arn        = local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn
}

# trivy:ignore:AVD-AWS-0089 S3 bucket logging ignored for this use case, but can be enabled by customers themselves if needed
# trivy:ignore:AVD-AWS-0090 Versioning is only enabled for backups; lease objects change on every renewal
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
}

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "KMS key for ${var.bucket_name} bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  count = local.versioning_enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Access policy to attach to the ECS task role.
#
#   - aws:RequestedRegion pins S3 API calls to the bucket's region.
#   - aws:SecureTransport forces TLS on object operations.
#   - kms:ViaService uses a wildcard region: with bucket keys, S3 can route KMS calls
#     through unexpected regional endpoints, and pinning one region caused 403s.
resource "aws_iam_policy" "access" {
  name = "${var.bucket_name}-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowS3BucketAccess"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.this.arn
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.aws_region }
        }
      },
      {
        Sid      = "AllowS3ObjectAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.this.arn}/*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.aws_region }
          Bool         = { "aws:SecureTransport" = "true" }
        }
      },
      {
        Sid      = "AllowKMSAccess"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = local.kms_key_arn
        Condition = {
          StringLike = { "kms:ViaService" = "s3.*.amazonaws.com" }
        }
      }
    ]
  })
}
