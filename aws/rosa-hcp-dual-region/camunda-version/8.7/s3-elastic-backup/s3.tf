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
          "s3:*"
        ],
        Resource = [
          aws_s3_bucket.elastic_backup.arn,
          "${aws_s3_bucket.elastic_backup.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "s3_access_attachment" {
  user       = aws_iam_user.service_account.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
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
