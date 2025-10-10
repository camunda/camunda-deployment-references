locals {
  opensearch_domain_name    = substr("${var.prefix}-os", 0, 28) # OpenSearch domain name must be <= 28 characters
  opensearch_enable_logging = false
  opensearch_enable         = true
  opensearch_architecture   = "x86_64" # Default architecture, can be overridden by the user
  opensearch_instance_type = {
    x86_64 = "m7i.large.search"
    arm64  = "m7g.large.search"
  }
  opensearch_dedicated_master_type = {
    x86_64 = "m7i.large.search"
    arm64  = "m7g.large.search"
  }
  # The types of logs to publish to CloudWatch Logs
  # Audit logs are only possible with advanced security options
  opensearch_log_types = ["SEARCH_SLOW_LOGS", "INDEX_SLOW_LOGS", "ES_APPLICATION_LOGS"]
}
module "opensearch_domain" {
  // for additional information on the module, see:
  // https://github.com/camunda/camunda-deployment-references/tree/main/aws/modules/opensearch

  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/opensearch"

  count = local.opensearch_enable ? 1 : 0

  domain_name = local.opensearch_domain_name
  # renovate: datasource=custom.opensearch-camunda depName=opensearch versioning=loose
  engine_version = "2.19"
  subnet_ids     = module.vpc.private_subnets
  vpc_id         = module.vpc.vpc_id
  cidr_blocks    = module.vpc.private_subnets_cidr_blocks

  instance_type   = local.opensearch_instance_type[local.opensearch_architecture]
  instance_count  = 3
  ebs_volume_size = 50

  dedicated_master_type = local.opensearch_dedicated_master_type[local.opensearch_architecture]

  advanced_security_enabled = false

  log_types = local.opensearch_enable_logging ? local.opensearch_log_types : []

  access_policies = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "es:*",
      "Resource": "arn:aws:es:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
    }
  ]
}
EOF
}

# Outputs of the parent module
output "aws_opensearch_domain" {
  value       = "https://${join("", module.opensearch_domain[*].opensearch_domain_endpoint)}"
  description = "(Optional) The endpoint of the OpenSearch domain."
}

output "aws_opensearch_domain_name" {
  value       = local.opensearch_enable ? local.opensearch_domain_name : ""
  description = "The name of the OpenSearch domain."
}
