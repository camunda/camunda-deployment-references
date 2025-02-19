locals {
  opensearch_domain_name = "domain-name-os-std" # Replace "domain-name" with your domain name
}

module "opensearch_domain" {
  source         = "git::https://github.com/camunda/camunda-tf-eks-module//modules/opensearch?ref=3.1.3"
  domain_name    = local.opensearch_domain_name
  engine_version = "2.15"

  instance_type = "m7i.large.search"

  instance_count  = 3 # one instance per AZ
  ebs_volume_size = 50

  subnet_ids  = module.eks_cluster.private_subnet_ids
  vpc_id      = module.eks_cluster.vpc_id
  cidr_blocks = concat(module.eks_cluster.private_vpc_cidr_blocks, module.eks_cluster.public_vpc_cidr_blocks)

  advanced_security_enabled = false # disable fine-grained

  advanced_security_internal_user_database_enabled = false
  advanced_security_anonymous_auth_enabled         = true # rely on anonymous auth

  # allow unauthentificated access as managed OpenSearch only allows fine tuned and no Basic Auth
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
