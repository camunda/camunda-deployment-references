resource "aws_s3_bucket" "s3_backup" {
  bucket = "${var.prefix}-backup-bucket"

  force_destroy = true
}

resource "aws_iam_policy" "s3_backup_access_policy" {
  name        = "${var.prefix}-s3-backup-access-policy"
  description = "Policy for accessing S3 backup bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:*"
        ],
        Resource = [
          aws_s3_bucket.s3_backup.arn,
          "${aws_s3_bucket.s3_backup.arn}/*"
        ]
      }
    ]
  })
}
