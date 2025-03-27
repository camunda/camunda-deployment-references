locals {
  eks_cluster_name   = "cluster-name-irsa" # Change this to a name of your choice
  eks_cluster_region = "eu-north-1"        # Change this to your desired AWS region
  # renovate: datasource=endoflife-date depName=amazon-eks versioning=loose
  kubernetes_version = "1.32" # Change this to your desired Kubernetes version (eks - major.minor)
}

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  name   = local.eks_cluster_name
  region = local.eks_cluster_region

  kubernetes_version = local.kubernetes_version

  # Set CIDR ranges or use the defaults
  cluster_service_ipv4_cidr = "10.190.0.0/16"
  cluster_node_ipv4_cidr    = "10.192.0.0/16"

  # Default node type for the Kubernetes cluster
  np_instance_types     = ["m6i.xlarge"]
  np_desired_node_count = 4
}

output "cert_manager_arn" {
  value       = module.eks_cluster.cert_manager_arn
  description = "The Amazon Resource Name (ARN) of the AWS IAM Roles for Service Account mapping for the cert-manager"
}

output "external_dns_arn" {
  value       = module.eks_cluster.external_dns_arn
  description = "The Amazon Resource Name (ARN) of the AWS IAM Roles for Service Account mapping for the external-dns"
}
