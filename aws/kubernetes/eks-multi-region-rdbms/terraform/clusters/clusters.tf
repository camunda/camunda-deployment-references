################################################################################
# Cluster creation, one EKS cluster per active region slot                     #
#                                                                              #
# The EKS module's nested upstream modules require statically associated AWS     #
# providers, so each slot is explicit and count-gated. Slots activate in order, #
# preserving Zeebe region IDs and EKS resource addresses as regions are added.  #
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

  # EKS and its nested upstream modules require a statically associated provider.
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
