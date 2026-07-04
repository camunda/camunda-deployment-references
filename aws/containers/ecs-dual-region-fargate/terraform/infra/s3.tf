################################################################
#            Backup S3 Bucket (single, shared by both regions) #
#                                                              #
# Both regions write backups to this bucket and restore from   #
# it. A single shared bucket ensures all backup data is in     #
# one place, regardless of which region is active.             #
################################################################

# Region 0 backup bucket
#trivy:ignore:AVD-AWS-0089 Bucket logging disabled to simplify setup
resource "aws_s3_bucket" "backup_region_0" {
  bucket        = "${local.prefix_region_0}-backup-${local.bucket_suffix}"
  force_destroy = var.s3_force_destroy
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

