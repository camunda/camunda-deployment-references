# KMS key for S3 bucket encryption
resource "aws_kms_key" "s3_bucket_key" {
  description             = "KMS key for ${var.cluster_name} S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-s3-kms-key"
  }
}

resource "aws_kms_alias" "s3_bucket_key_alias" {
  name          = "alias/${var.cluster_name}-s3-bucket-key"
  target_key_id = aws_kms_key.s3_bucket_key.key_id
}

# Main backup bucket
#trivy:ignore:AVD-AWS-0089 Bucket logging disabled - logs bucket removed to simplify setup
resource "aws_s3_bucket" "elastic_backup" {
  bucket = "${var.cluster_name}-elastic-backup"

  tags = {
    Name = var.cluster_name
  }

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "elastic_backup" {
  bucket = aws_s3_bucket.elastic_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "elastic_backup" {
  bucket = aws_s3_bucket.elastic_backup.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_bucket_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "elastic_backup" {
  bucket = aws_s3_bucket.elastic_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

# IAM user for S3 access
#trivy:ignore:AVD-AWS-0143 Accepted risk for demonstration purposes - using IAM user instead of role/group
resource "aws_iam_user" "service_account" {
  name = "${var.cluster_name}-s3-service-account"

  tags = {
    Name = "${var.cluster_name}-s3-service-account"
  }
}

resource "aws_iam_access_key" "service_account_access_key" {
  user = aws_iam_user.service_account.name
}

resource "aws_iam_policy" "s3_access_policy" {
  name        = "${var.cluster_name}-s3-access-policy"
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
          aws_s3_bucket.elastic_backup.arn,
          "${aws_s3_bucket.elastic_backup.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = [
          aws_kms_key.s3_bucket_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "s3_access_attachment" {
  user       = aws_iam_user.service_account.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}
