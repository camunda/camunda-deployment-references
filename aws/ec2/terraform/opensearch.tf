locals {
  opensearch_domain_name = "${var.prefix}-os-cluster"
}
module "opensearch_domain" {
  // for additional information on the module, see:
  // https://github.com/camunda/camunda-tf-eks-module/tree/main/modules/opensearch

  # tflint-ignore: terraform_module_pinned_source
  source = "github.com/camunda/camunda-tf-eks-module//modules/opensearch"

  count = var.enable_opensearch ? 1 : 0

  domain_name    = local.opensearch_domain_name
  engine_version = var.opensearch_engine_version
  subnet_ids     = module.vpc.private_subnets
  vpc_id         = module.vpc.vpc_id
  cidr_blocks    = module.vpc.private_subnets_cidr_blocks

  instance_type   = var.opensearch_instance_type[var.opensearch_architecture]
  instance_count  = var.opensearch_instance_count
  ebs_volume_size = var.opensearch_disk_size

  dedicated_master_type = var.opensearch_dedicated_master_type[var.opensearch_architecture]

  advanced_security_enabled = false

  log_types = var.enable_opensearch_logging ? var.opensearch_log_types : []

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
      "Resource": "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
    }
  ]
}
EOF
}
