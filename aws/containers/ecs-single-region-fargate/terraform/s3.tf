# S3 bucket
resource "aws_s3_bucket" "main" {
  bucket_prefix = "${var.prefix}-bucket"
}

# Block public access
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM user for S3 access
resource "aws_iam_user" "s3_user" {
  name = "${var.prefix}-user"

  tags = {
    Description = "User for S3 bucket access"
  }
}

# Access key for the IAM user
resource "aws_iam_access_key" "s3_user_key" {
  user = aws_iam_user.s3_user.name
}

# IAM policy for S3 bucket access
resource "aws_iam_user_policy" "s3_user_policy" {
  name = "${var.prefix}-s3-access-policy"
  user = aws_iam_user.s3_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.main.arn}/*"
      }
    ]
  })
}

# Outputs
output "s3_bucket_name" {
  value       = aws_s3_bucket.main.id
  description = "The name of the S3 bucket"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.main.arn
  description = "The ARN of the S3 bucket"
}

output "s3_access_key_id" {
  value       = aws_iam_access_key.s3_user_key.id
  description = "The access key ID for S3 bucket access"
  sensitive   = true
}

output "s3_secret_access_key" {
  value       = aws_iam_access_key.s3_user_key.secret
  description = "The secret access key for S3 bucket access"
  sensitive   = true
}
