################################################################
#           OpenSearch (alternative to Aurora Global)           #
################################################################

module "opensearch_region_0" {
  count  = var.secondary_storage_type == "opensearch" ? 1 : 0
  source = "../../../../modules/opensearch"

  domain_name = "${local.prefix_region_0}-opensearch"
  vpc_id      = module.vpc_region_0.vpc_id
  subnet_ids  = [module.vpc_region_0.private_subnets[0]]
  cidr_blocks = [local.owner.vpc_cidr_block, local.accepter.vpc_cidr_block]

  instance_type  = "t3.medium.search"
  instance_count = 1

  dedicated_master_enabled = false
  zone_awareness_enabled   = false

  advanced_security_enabled                        = true
  advanced_security_internal_user_database_enabled = true
  advanced_security_master_user_name               = var.db_admin_username
  advanced_security_master_user_password           = local.db_admin_password_effective

  tags = {
    Name = "${local.prefix_region_0}-opensearch"
  }
}

module "opensearch_region_1" {
  count  = var.secondary_storage_type == "opensearch" ? 1 : 0
  source = "../../../../modules/opensearch"

  providers = {
    aws = aws.accepter
  }

  domain_name = "${local.prefix_region_1}-opensearch"
  vpc_id      = module.vpc_region_1.vpc_id
  subnet_ids  = [module.vpc_region_1.private_subnets[0]]
  cidr_blocks = [local.owner.vpc_cidr_block, local.accepter.vpc_cidr_block]

  instance_type  = "t3.medium.search"
  instance_count = 1

  dedicated_master_enabled = false
  zone_awareness_enabled   = false

  advanced_security_enabled                        = true
  advanced_security_internal_user_database_enabled = true
  advanced_security_master_user_name               = var.db_admin_username
  advanced_security_master_user_password           = local.db_admin_password_effective

  tags = {
    Name = "${local.prefix_region_1}-opensearch"
  }
}
