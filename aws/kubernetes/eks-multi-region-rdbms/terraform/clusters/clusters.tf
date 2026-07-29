################################################################################
# Cluster creation, one EKS cluster per active region slot                     #
#                                                                              #
# Terraform providers cannot be iterated, so each slot is written out           #
# explicitly and gated with `count`. Slots are activated in order, which keeps  #
# the Zeebe region IDs and the AWS resource addresses stable when a region is   #
# added later.                                                                 #
################################################################################

module "eks_cluster_region_0" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/eks-cluster"

  count = var.active_region_count > 0 ? 1 : 0

  region                = var.regions[0].region
  name                  = "${var.cluster_name}-${var.regions[0].short_name}"
  kubernetes_version    = var.kubernetes_version
  np_instance_types     = var.np_instance_types
  np_capacity_type      = var.np_capacity_type
  np_max_node_count     = var.np_max_node_count
  np_desired_node_count = var.np_desired_node_count
  single_nat_gateway    = var.single_nat_gateway

  cluster_service_ipv4_cidr = var.regions[0].service_cidr_block
  cluster_node_ipv4_cidr    = var.regions[0].vpc_cidr_block
}

module "eks_cluster_region_1" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/eks-cluster"

  count = var.active_region_count > 1 ? 1 : 0

  region                = var.regions[1].region
  name                  = "${var.cluster_name}-${var.regions[1].short_name}"
  kubernetes_version    = var.kubernetes_version
  np_instance_types     = var.np_instance_types
  np_capacity_type      = var.np_capacity_type
  np_max_node_count     = var.np_max_node_count
  np_desired_node_count = var.np_desired_node_count
  single_nat_gateway    = var.single_nat_gateway

  cluster_service_ipv4_cidr = var.regions[1].service_cidr_block
  cluster_node_ipv4_cidr    = var.regions[1].vpc_cidr_block

  # Every resource of a non-default region must be pinned to its provider alias,
  # otherwise it is silently created in the default region.
  providers = {
    aws = aws.region_1
  }
}

module "eks_cluster_region_2" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/eks-cluster"

  count = var.active_region_count > 2 ? 1 : 0

  region                = var.regions[2].region
  name                  = "${var.cluster_name}-${var.regions[2].short_name}"
  kubernetes_version    = var.kubernetes_version
  np_instance_types     = var.np_instance_types
  np_capacity_type      = var.np_capacity_type
  np_max_node_count     = var.np_max_node_count
  np_desired_node_count = var.np_desired_node_count
  single_nat_gateway    = var.single_nat_gateway

  cluster_service_ipv4_cidr = var.regions[2].service_cidr_block
  cluster_node_ipv4_cidr    = var.regions[2].vpc_cidr_block

  providers = {
    aws = aws.region_2
  }
}

module "eks_cluster_region_3" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/eks-cluster"

  count = var.active_region_count > 3 ? 1 : 0

  region                = var.regions[3].region
  name                  = "${var.cluster_name}-${var.regions[3].short_name}"
  kubernetes_version    = var.kubernetes_version
  np_instance_types     = var.np_instance_types
  np_capacity_type      = var.np_capacity_type
  np_max_node_count     = var.np_max_node_count
  np_desired_node_count = var.np_desired_node_count
  single_nat_gateway    = var.single_nat_gateway

  cluster_service_ipv4_cidr = var.regions[3].service_cidr_block
  cluster_node_ipv4_cidr    = var.regions[3].vpc_cidr_block

  providers = {
    aws = aws.region_3
  }
}

locals {
  # Uniform view over the count-gated modules so that the rest of the
  # configuration can index by region slot instead of repeating ternaries.
  clusters = {
    for i, m in [
      module.eks_cluster_region_0,
      module.eks_cluster_region_1,
      module.eks_cluster_region_2,
      module.eks_cluster_region_3,
    ] : i => one(m) if length(m) > 0
  }
}
