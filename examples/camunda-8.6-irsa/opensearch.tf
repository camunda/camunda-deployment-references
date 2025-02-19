locals {
  opensearch_domain_name = "domain-name-os-irsa" # Replace "domain-name" with your domain name

  opensearch_master_username = "secret_user"    # Replace with your opensearch username
  opensearch_master_password = "Secretvalue$23" # Replace with your opensearch password, password must contain at least one uppercase letter, one lowercase letter, one number, and one special character.

  opensearch_iam_role_name = "OpenSearchRole-${local.opensearch_domain_name}" # Ensure uniqueness

  # IRSA configuration
  camunda_namespace                = "camunda"     # Replace with your Kubernetes namespace that will host C8 Platform
  camunda_zeebe_service_account    = "zeebe-sa"    # Replace with your Kubernetes ServiceAcccount that will be created for Zeebe
  camunda_operate_service_account  = "operate-sa"  # Replace with your Kubernetes ServiceAcccount that will be created for Operate
  camunda_tasklist_service_account = "tasklist-sa" # Replace with your Kubernetes ServiceAcccount that will be created for TaskList
  camunda_optimize_service_account = "optimize-sa" # Replace with your Kubernetes ServiceAcccount that will be created for Optimize
}

module "opensearch_domain" {
  source         = "git::https://github.com/camunda/camunda-tf-eks-module//modules/opensearch?ref=3.1.3"
  domain_name    = local.opensearch_domain_name
  engine_version = "2.15"

  instance_type   = "m7i.large.search"
  instance_count  = 3 # one instance per AZ
  ebs_volume_size = 50

  subnet_ids  = module.eks_cluster.private_subnet_ids
  vpc_id      = module.eks_cluster.vpc_id
  cidr_blocks = concat(module.eks_cluster.private_vpc_cidr_blocks, module.eks_cluster.public_vpc_cidr_blocks)

  advanced_security_enabled                        = true
  advanced_security_internal_user_database_enabled = true

  advanced_security_master_user_name     = local.opensearch_master_username
  advanced_security_master_user_password = local.opensearch_master_password

  # IAM IRSA
  iam_roles_with_policies = [
    {
      role_name    = local.opensearch_iam_role_name
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
                    "${module.eks_cluster.oidc_provider_id}:sub": [
                      "system:serviceaccount:${local.camunda_namespace}:${local.camunda_zeebe_service_account}",
                      "system:serviceaccount:${local.camunda_namespace}:${local.camunda_operate_service_account}",
                      "system:serviceaccount:${local.camunda_namespace}:${local.camunda_tasklist_service_account}",
                      "system:serviceaccount:${local.camunda_namespace}:${local.camunda_optimize_service_account}"
                    ]
                  }
                }
              }
            ]
          }
EOF

      access_policy = <<EOF
            {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Effect": "Allow",
                  "Action": [
                    "es:DescribeElasticsearchDomains",
                    "es:DescribeElasticsearchInstanceTypeLimits",
                    "es:DescribeReservedElasticsearchInstanceOfferings",
                    "es:DescribeReservedElasticsearchInstances",
                    "es:GetCompatibleElasticsearchVersions",
                    "es:ListDomainNames",
                    "es:ListElasticsearchInstanceTypes",
                    "es:ListElasticsearchVersions",
                    "es:DescribeElasticsearchDomain",
                    "es:DescribeElasticsearchDomainConfig",
                    "es:ESHttpGet",
                    "es:ESHttpHead",
                    "es:GetUpgradeHistory",
                    "es:GetUpgradeStatus",
                    "es:ListTags",
                    "es:AddTags",
                    "es:RemoveTags",
                    "es:ESHttpDelete",
                    "es:ESHttpPost",
                    "es:ESHttpPut"
                  ],
                  "Resource": "arn:aws:es:${local.eks_cluster_region}:${module.eks_cluster.aws_caller_identity_account_id}:domain/${local.opensearch_domain_name}/*"
                }
              ]
            }
EOF
    }
  ]


  # rely on fine grained access control for this part
  access_policies = <<CONFIG
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "es:*",
      "Resource": "arn:aws:es:${local.eks_cluster_region}:${module.eks_cluster.aws_caller_identity_account_id}:domain/${local.opensearch_domain_name}/*"
    }
  ]
}
CONFIG


  depends_on = [module.eks_cluster]
}

output "opensearch_endpoint" {
  value       = module.opensearch_domain.opensearch_domain_endpoint
  description = "The OpenSearch endpoint URL"
}

output "opensearch_iam_role_arns" {
  value       = module.opensearch_domain.opensearch_iam_role_arns
  description = "Map of IAM role names to their ARNs"
}
