locals {
  account_role_prefix  = "${var.cluster_name}-account"
  operator_role_prefix = "${var.cluster_name}-operator"

  tags = {
    "owner" = data.aws_caller_identity.current.arn
  }

  availability_zones_count_computed = var.availability_zones == null ? var.availability_zones_count : (length(var.availability_zones) > 0 ? length(var.availability_zones) : var.availability_zones_count)
}

data "aws_servicequotas_service_quota" "elastic_ip_quota" {
  service_code = "ec2"
  quota_code   = "L-0263D0A3" # Quota code for Elastic IP addresses per region
}


data "aws_eips" "current_usage" {}

# Data source to check if the VPC exists
data "aws_vpcs" "current_vpcs" {
  tags = merge({
    Name = "${var.cluster_name}-vpc"
  }, var.tags)
}

check "elastic_ip_quota_check" {

  # Only check the condition when no existing vpc is there.
  assert {
    condition     = length(data.aws_vpcs.current_vpcs.ids) > 0 || (data.aws_servicequotas_service_quota.elastic_ip_quota.value - length(data.aws_eips.current_usage.public_ips)) >= local.availability_zones_count_computed
    error_message = "Not enough available Elastic IPs to cover all local availability zones (need: ${local.availability_zones_count_computed}, have: ${(data.aws_servicequotas_service_quota.elastic_ip_quota.value - length(data.aws_eips.current_usage.public_ips))})."
  }
}

module "rosa_hcp" {
  source  = "terraform-redhat/rosa-hcp/rhcs"
  version = "1.7.1"

  openshift_version = var.openshift_version
  cluster_name      = var.cluster_name
  private           = var.private

  compute_machine_type = var.compute_node_instance_type
  tags                 = merge(local.tags, var.tags)

  machine_cidr = var.machine_cidr_block
  service_cidr = var.service_cidr_block
  pod_cidr     = var.pod_cidr_block
  properties   = { rosa_creator_arn = data.aws_caller_identity.current.arn }


  replicas               = var.replicas
  aws_availability_zones = length(var.aws_availability_zones) > 0 ? var.aws_availability_zones : module.vpc.availability_zones

  aws_subnet_ids = var.private ? module.vpc.private_subnets : concat(
    module.vpc.public_subnets,
    module.vpc.private_subnets
  )

  host_prefix = var.host_prefix

  // STS configuration
  create_account_roles  = true
  account_role_prefix   = local.account_role_prefix
  create_oidc           = true
  create_operator_roles = true
  operator_role_prefix  = local.operator_role_prefix

  wait_for_create_complete            = true
  wait_for_std_compute_nodes_complete = true

  depends_on = [
    module.vpc,
  ]
}

module "htpasswd_idp" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/idp"
  version = "1.7.1"

  cluster_id         = module.rosa_hcp.cluster_id
  name               = "htpasswd-idp"
  idp_type           = "htpasswd"
  htpasswd_idp_users = [{ username = var.htpasswd_username, password = var.htpasswd_password }]
}

module "vpc" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/vpc"
  version = "1.7.1"

  name_prefix = var.cluster_name

  availability_zones_count = var.availability_zones != null ? null : var.availability_zones_count
  availability_zones       = var.availability_zones

  vpc_cidr = var.vpc_cidr_block
}
