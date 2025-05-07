resource "aws_s3_bucket" "elastic_backup" {
  bucket = "ccon25-nl-elastic-backup"

  tags = {
    Name = "ccon25-nl-elastic-backup"
  }

  force_destroy = true
}

resource "aws_iam_user" "service_account" {
  name = "ccon25-nl-s3-service-account"
}

resource "aws_iam_access_key" "service_account_access_key" {
  user = aws_iam_user.service_account.name
}

resource "aws_iam_policy" "s3_access_policy" {
  name        = "ccon25-nl-s3-access-policy"
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
