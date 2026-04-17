################################################################
#               Backup S3 Buckets (per region)                 #
################################################################

# Region 0 backup bucket
# Bucket name includes account ID for global uniqueness across deployments.
# force_destroy = true allows `terraform destroy` to succeed even when the bucket
# contains backup objects. Safe for experiments; set to false in production.
#trivy:ignore:AVD-AWS-0089 Bucket logging disabled to simplify setup
resource "aws_s3_bucket" "backup_region_0" {
  bucket        = "${local.prefix_region_0}-backup-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "backup_region_0" {
  bucket = aws_s3_bucket.backup_region_0.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_region_0" {
  bucket = aws_s3_bucket.backup_region_0.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_region_0.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "backup_region_0" {
  bucket = aws_s3_bucket.backup_region_0.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Region 1 backup bucket
# Bucket name includes account ID for global uniqueness across deployments.
# Note: cross-region restore (region 0 reading from region 1's bucket) requires
# Multi-Region KMS keys. The current per-region KMS keys only allow same-region access.
#trivy:ignore:AVD-AWS-0089 Bucket logging disabled to simplify setup
resource "aws_s3_bucket" "backup_region_1" {
  provider      = aws.accepter
  bucket        = "${local.prefix_region_1}-backup-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.s3_force_destroy
}

resource "aws_s3_bucket_public_access_block" "backup_region_1" {
  provider = aws.accepter
  bucket   = aws_s3_bucket.backup_region_1.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_region_1" {
  provider = aws.accepter
  bucket   = aws_s3_bucket.backup_region_1.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_region_1.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "backup_region_1" {
  provider = aws.accepter
  bucket   = aws_s3_bucket.backup_region_1.id

  versioning_configuration {
    status = "Enabled"
  }
}

################################################################
#               S3 Backup Access Policies                      #
################################################################

resource "aws_iam_policy" "s3_backup_access_region_0" {
  name        = "${local.prefix_region_0}-s3-backup-access"
  description = "S3 backup bucket access for region 0"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.backup_region_0.arn,
          "${aws_s3_bucket.backup_region_0.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.s3_region_0.arn]
      }
    ]
  })
}

resource "aws_iam_policy" "s3_backup_access_region_1" {
  provider = aws.accepter

  name        = "${local.prefix_region_1}-s3-backup-access"
  description = "S3 backup bucket access for region 1"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.backup_region_1.arn,
          "${aws_s3_bucket.backup_region_1.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.s3_region_1.arn]
      }
    ]
  })
}
