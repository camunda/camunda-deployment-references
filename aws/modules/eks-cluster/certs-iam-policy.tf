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


module "external_secrets_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.58.0"

  role_name = "${var.name}-eso-role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.certs_access_policy.arn
  }
}


output "secret_manager_arn" {
  value       = module.external_secrets_role.iam_role_arn
  description = "Amazon Resource Name of the secret-manager IAM role used for IAM Roles to Service Accounts mappings"
}
