locals {
  rosa_cluster_1_name = "cluster-region-1" # Change this to a name of your choice

  rosa_cluster_1_zones = ["${var.cluster_1_region}a", "${var.cluster_1_region}b", "${var.cluster_1_region}c"] # Adjust to your needs and align with your value of AWS_REGION

  rosa_cluster_1_admin_username = "kubeadmin"
  rosa_cluster_1_admin_password = "CHANGEME1234r!" # Change the password of your admin password

  rosa_cluster_1_vpc_cidr_block     = "10.0.0.0/16"
  rosa_cluster_1_machine_cidr_block = "10.0.0.0/18"
  rosa_cluster_1_service_cidr_block = "10.0.128.0/18"
  rosa_cluster_1_pod_cidr_block     = "10.0.64.0/18"

  rosa_cluster_1_tags = {} # additional tags that you may want to apply to the resources
}

module "rosa_cluster_1" {
  providers = {
    aws = aws.cluster_1
  }

  source = "../../../../modules/rosa-hcp"

  cluster_name = local.rosa_cluster_1_name

  availability_zones = local.rosa_cluster_1_zones

  # Set CIDR ranges or use the defaults
  vpc_cidr_block     = local.rosa_cluster_1_vpc_cidr_block
  machine_cidr_block = local.rosa_cluster_1_machine_cidr_block
  service_cidr_block = local.rosa_cluster_1_service_cidr_block
  pod_cidr_block     = local.rosa_cluster_1_pod_cidr_block

  # admin access
  htpasswd_username = local.rosa_cluster_1_admin_username
  htpasswd_password = local.rosa_cluster_1_admin_password

  # Default node type for the OpenShift cluster
  compute_node_instance_type = "m7i.xlarge"
  replicas                   = 6

  tags = local.rosa_cluster_1_tags
}

# Outputs of the parent module

output "cluster_1_public_subnet_ids" {
  value       = module.rosa_cluster_1.public_subnet_ids
  description = "A comma-separated list of public subnet IDs in the VPC. These subnets are typically used for resources that require internet access."
}

output "cluster_1_private_subnet_ids" {
  value       = module.rosa_cluster_1.private_subnet_ids
  description = "A comma-separated list of private subnet IDs in the VPC. These subnets are typically used for internal resources that do not require direct internet access."
}
output "cluster_1_vpc_id" {
  value       = module.rosa_cluster_1.vpc_id
  description = "The VPC ID of the cluster."
}

output "cluster_1_cluster_id" {
  value       = module.rosa_cluster_1.cluster_id
  description = "The unique identifier of the OpenShift cluster created on Red Hat OpenShift Service on AWS (ROSA). This ID is used to reference the cluster in subsequent operations."
}

output "cluster_1_oidc_provider_id" {
  value       = module.rosa_cluster_1.oidc_provider_id
  description = "OIDC provider for the ROSA cluster. Allows adding additional IAM Role for Service Accounts (IRSA) mappings."
}

output "cluster_1_aws_caller_identity_account_id" {
  value       = module.rosa_cluster_1.aws_caller_identity_account_id
  description = "The AWS account ID of the caller. This is the account under which the Terraform code is being executed."
}

output "cluster_1_openshift_api_url" {
  value       = module.rosa_cluster_1.openshift_api_url
  description = "The endpoint URL for accessing the OpenShift API. This endpoint is used to interact with the OpenShift cluster's API server."
}

output "cluster_1_cluster_console_url" {
  value       = module.rosa_cluster_1.cluster_console_url
  description = "The URL endpoint for accessing the OpenShift web console. This endpoint provides a web-based user interface for managing the OpenShift cluster."
}
