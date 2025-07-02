# This file describes permissions for a EKS SA to access ASS

resource "aws_iam_policy" "certs_access_policy" {
  name = "${var.name}-certs-access-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ],
        Resource = "arn:aws:secretsmanager:::secret:certs/*"
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:ListSecrets"
        ],
        Resource = "*"
      }
    ]
  })
}
