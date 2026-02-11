locals {
  aurora_cluster_name = "cluster-name-pg-irsa" # Replace "cluster-name" with your cluster's name

  aurora_master_username = "secret_user"    # Replace with your Aurora username
  aurora_master_password = "secretvalue%23" # Replace with your Aurora password, password must contain at least one letter, one number, and one special character.

  # Database names for Camunda components
  camunda_database_identity   = "camunda_identity"   # Name of your camunda database for Identity
  camunda_database_webmodeler = "camunda_webmodeler" # Name of your camunda database for WebModeler

  # IRSA configuration
  camunda_identity_db_username   = "identity_irsa"   # This is the username that will be used for IRSA connection to the DB on Identity db
  camunda_webmodeler_db_username = "webmodeler_irsa" # This is the username that will be used for IRSA connection to the DB on WebModeler db

  camunda_identity_service_account   = "identity-sa"   # Replace with your Kubernetes ServiceAcccount that will be created for Identity
  camunda_webmodeler_service_account = "webmodeler-sa" # Replace with your Kubernetes ServiceAcccount that will be created for WebModeler

  camunda_identity_role_name   = "AuroraRole-Identity-${local.aurora_cluster_name}"   # IAM Role name use to allow access to the identity db
  camunda_webmodeler_role_name = "AuroraRole-Webmodeler-${local.aurora_cluster_name}" # IAM Role name use to allow access to the webmodeler db

  db_tags = {} # additional tags that you may want to apply to the resources
}

module "postgresql" {
  source = "../../../../modules/aurora"
  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  engine_version             = "17.7"
  auto_minor_version_upgrade = false
  cluster_name               = local.aurora_cluster_name
  default_database_name      = local.camunda_database_identity

  availability_zones = ["${local.eks_cluster_region}a", "${local.eks_cluster_region}b", "${local.eks_cluster_region}c"]

  username = local.aurora_master_username
  password = local.aurora_master_password

  vpc_id      = module.eks_cluster.vpc_id
  subnet_ids  = module.eks_cluster.private_subnet_ids
  cidr_blocks = concat(module.eks_cluster.private_vpc_cidr_blocks, module.eks_cluster.public_vpc_cidr_blocks)

  num_instances  = "1" # only one instance, you can add add other read-only instances if you want
  instance_class = "db.t3.medium"

  # IAM IRSA - Identity and WebModeler
  iam_auth_enabled = true
  iam_roles_with_policies = [
    {
      role_name    = local.camunda_identity_role_name
      trust_policy = <<EOF
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "Principal": {
                  "Federated": "${module.eks_cluster.oidc_provider_arn}"
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                  "StringEquals": {
                    "${module.eks_cluster.oidc_provider_id}:sub": "system:serviceaccount:${local.camunda_namespace}:${local.camunda_identity_service_account}"
                  }
                }
              }
            ]
          }
EOF

      # Source: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html
      access_policy = <<EOF
           {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Effect": "Allow",
                  "Action": [
                    "rds-db:connect"
                  ],
                  "Resource": "arn:aws:rds-db:${local.eks_cluster_region}:${module.eks_cluster.aws_caller_identity_account_id}:dbuser:*/${local.camunda_identity_db_username}"
                }
              ]
            }
EOF

    },

    {
      role_name    = local.camunda_webmodeler_role_name
      trust_policy = <<EOF
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "Principal": {
                  "Federated": "${module.eks_cluster.oidc_provider_arn}"
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                  "StringEquals": {
                    "${module.eks_cluster.oidc_provider_id}:sub": "system:serviceaccount:${local.camunda_namespace}:${local.camunda_webmodeler_service_account}"
                  }
                }
              }
            ]
          }
EOF

      # Same rationale as the above for access policy
      access_policy = <<EOF
            {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Effect": "Allow",
                  "Action": [
                    "rds-db:connect"
                  ],
                  "Resource": "arn:aws:rds-db:${local.eks_cluster_region}:${module.eks_cluster.aws_caller_identity_account_id}:dbuser:*/${local.camunda_webmodeler_db_username}"
                }
              ]
            }
EOF

    }
  ]

  tags       = local.db_tags
  depends_on = [module.eks_cluster]
}

output "postgres_endpoint" {
  value       = module.postgresql.aurora_endpoint
  description = "The Postgres endpoint URL"
}

output "aurora_iam_role_arns" {
  value       = module.postgresql.aurora_iam_role_arns
  description = "Map of IAM role names to their ARNs"
}
