# Keycloak IRSA trust for Aurora access (CI/Test only)
#
# Adds an IRSA trust relationship between an IAM role with Aurora PostgreSQL
# access and the Kubernetes ServiceAccount for Keycloak.
# The actual database setup (user, grants) remains a separate step.
#
# Copy this file to terraform/cluster/ when using embedded Keycloak instead of external OIDC.

locals {
  # Keycloak-specific database configuration for IRSA
  camunda_database_keycloak        = "camunda_keycloak"                                 # Name of your camunda database for Keycloak
  camunda_keycloak_db_username     = "keycloak_irsa"                                    # Username for IRSA connection to the DB on Keycloak db
  camunda_keycloak_service_account = "keycloak-sa"                                      # Kubernetes ServiceAccount for Keycloak
  camunda_keycloak_role_name       = "AuroraRole-Keycloak-${local.aurora_cluster_name}" # IAM Role name for Keycloak db access
}

# Keycloak IAM role for IRSA DB access
resource "aws_iam_role" "keycloak_aurora" {
  name = local.camunda_keycloak_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks_cluster.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks_cluster.oidc_provider_id}:sub" = "system:serviceaccount:${local.camunda_namespace}:${local.camunda_keycloak_service_account}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "keycloak_aurora_access" {
  name        = "${local.camunda_keycloak_role_name}-access-policy"
  description = "Access policy for ${local.camunda_keycloak_role_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = "arn:aws:rds-db:${local.eks_cluster_region}:${module.eks_cluster.aws_caller_identity_account_id}:dbuser:*/${local.camunda_keycloak_db_username}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "keycloak_aurora" {
  role       = aws_iam_role.keycloak_aurora.name
  policy_arn = aws_iam_policy.keycloak_aurora_access.arn
}

output "keycloak_aurora_iam_role_arn" {
  value       = aws_iam_role.keycloak_aurora.arn
  description = "ARN of the Keycloak IAM role for Aurora IRSA access"
}
