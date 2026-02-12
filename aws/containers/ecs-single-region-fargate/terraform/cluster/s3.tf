# KMS key for S3 bucket encryption
resource "aws_kms_key" "s3_bucket_key" {
  description             = "KMS key for ${var.prefix} ECS S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.prefix}-s3-kms-key"
  }
}

resource "aws_kms_alias" "s3_bucket_key_alias" {
  name          = "alias/${var.prefix}-s3-backup-bucket-key"
  target_key_id = aws_kms_key.s3_bucket_key.key_id
}

# Main backup bucket
#trivy:ignore:AVD-AWS-0089 Bucket logging disabled - logs bucket removed to simplify setup
resource "aws_s3_bucket" "backup" {
  bucket = "${var.prefix}-backup-bucket"
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_bucket_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_policy" "s3_backup_access_policy" {
  name        = "${var.prefix}-s3-access-policy"
  description = "Policy for accessing S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ],
        Resource = [
          aws_kms_key.s3_bucket_key.arn
        ],
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}
