variable "bucket_name" {
  type        = string
  description = "Name of the bucket used to backup the platform"
  default     = "camunda-elastic-backup-rosa-dual"
}

resource "aws_s3_bucket" "elastic_backup" {
  bucket = var.bucket_name

  tags = {
    Name = var.bucket_name
  }
}

resource "aws_kms_key" "backup_bucket_key" {
  description             = "This key is used to encrypt bucket ${var.bucket_name}"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encrypt_bucket" {
  bucket = aws_s3_bucket.elastic_backup.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.backup_bucket_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encrypt_log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.backup_bucket_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}


resource "aws_s3_bucket_versioning" "versioning_backup" {
  bucket = aws_s3_bucket.elastic_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "versioning_logs" {
  bucket = aws_s3_bucket.log_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "this" {
  bucket        = aws_s3_bucket.elastic_backup.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "log/"
}

# trivy:ignore:AVD-AWS-0089
resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.bucket_name}-log"
}

resource "aws_s3_bucket_public_access_block" "block_public_policy" {
  bucket                  = aws_s3_bucket.elastic_backup.id
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  block_public_acls       = true
}

resource "aws_s3_bucket_public_access_block" "block_public_policy_logs" {
  bucket                  = aws_s3_bucket.log_bucket.id
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  block_public_acls       = true
}

# trivy:ignore:AVD-AWS-0143
resource "aws_iam_user" "service_account" {
  name = "${var.bucket_name}-s3-service-account"
}

resource "aws_iam_access_key" "service_account_access_key" {
  user = aws_iam_user.service_account.name
}

resource "aws_iam_policy" "s3_access_policy" {
  name        = "${var.bucket_name}-s3-access-policy"
  description = "Policy for accessing S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          # Bucket-level actions
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",

          # Object-level actions
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectAcl",
          "s3:PutObjectAcl",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:RestoreObject"
        ],
        Resource = [
          aws_s3_bucket.elastic_backup.arn,
          "${aws_s3_bucket.elastic_backup.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "kms_access_policy" {
  name        = "${var.bucket_name}-kms-access-policy"
  description = "Policy for accessing KMS key"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = aws_kms_key.backup_bucket_key.arn
      }
    ]
  })

}

resource "aws_iam_user_policy_attachment" "s3_access_attachment" {
  user       = aws_iam_user.service_account.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

resource "aws_iam_user_policy_attachment" "kms_access_attachment" {
  user       = aws_iam_user.service_account.name
  policy_arn = aws_iam_policy.kms_access_policy.arn
}

output "s3_aws_access_key" {
  value = aws_iam_access_key.service_account_access_key.id
}

output "s3_aws_secret_access_key" {
  value     = aws_iam_access_key.service_account_access_key.secret
  sensitive = true
}

output "s3_bucket_name" {
  value = aws_s3_bucket.elastic_backup.bucket
}
