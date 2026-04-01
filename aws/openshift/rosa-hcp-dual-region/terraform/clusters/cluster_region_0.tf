locals {
  rosa_cluster_0_name = "cluster-region-0" # Change this to a name of your choice

  rosa_cluster_0_zones = ["${var.cluster_0_region}a", "${var.cluster_0_region}b", "${var.cluster_0_region}c"] # Adjust to your needs and align with your value of AWS_REGION

  rosa_cluster_0_admin_username = "kubeadmin"
  rosa_cluster_0_admin_password = random_password.rosa_cluster_0_admin.result

  rosa_cluster_0_vpc_cidr_block     = "10.0.0.0/16"
  rosa_cluster_0_machine_cidr_block = "10.0.0.0/18"
  rosa_cluster_0_service_cidr_block = "10.0.128.0/18"
  rosa_cluster_0_pod_cidr_block     = "10.0.64.0/18"

  rosa_cluster_0_tags = {} # additional tags that you may want to apply to the resources
}

# Generate random password for ROSA cluster 0 admin
# To retrieve password after apply: terraform output -raw rosa_cluster_0_admin_password
resource "random_password" "rosa_cluster_0_admin" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

module "rosa_cluster_0" {
  providers = {
    aws = aws.cluster_0
  }

  source = "../../../../modules/rosa-hcp"

  cluster_name = local.rosa_cluster_0_name

  availability_zones = local.rosa_cluster_0_zones

  # Set CIDR ranges or use the defaults
  vpc_cidr_block     = local.rosa_cluster_0_vpc_cidr_block
  machine_cidr_block = local.rosa_cluster_0_machine_cidr_block
  service_cidr_block = local.rosa_cluster_0_service_cidr_block
  pod_cidr_block     = local.rosa_cluster_0_pod_cidr_block

  # admin access
  htpasswd_username = local.rosa_cluster_0_admin_username
  htpasswd_password = local.rosa_cluster_0_admin_password

  # Default node type for the OpenShift cluster
  compute_node_instance_type = "m7i.xlarge"
  replicas                   = 6

  tags = local.rosa_cluster_0_tags
}

# Outputs of the parent module

output "cluster_0_public_subnet_ids" {
  value       = module.rosa_cluster_0.public_subnet_ids
  description = "A comma-separated list of public subnet IDs in the VPC. These subnets are typically used for resources that require internet access."
}

output "cluster_0_private_subnet_ids" {
  value       = module.rosa_cluster_0.private_subnet_ids
  description = "A comma-separated list of private subnet IDs in the VPC. These subnets are typically used for internal resources that do not require direct internet access."
}
output "cluster_0_vpc_id" {
  value       = module.rosa_cluster_0.vpc_id
  description = "The VPC ID of the cluster."
}

output "cluster_0_cluster_id" {
  value       = module.rosa_cluster_0.cluster_id
  description = "The unique identifier of the OpenShift cluster created on Red Hat OpenShift Service on AWS (ROSA). This ID is used to reference the cluster in subsequent operations."
}

output "cluster_0_oidc_provider_id" {
  value       = module.rosa_cluster_0.oidc_provider_id
  description = "OIDC provider for the ROSA cluster. Allows adding additional IAM Role for Service Accounts (IRSA) mappings."
}

output "cluster_0_aws_caller_identity_account_id" {
  value       = module.rosa_cluster_0.aws_caller_identity_account_id
  description = "The AWS account ID of the caller. This is the account under which the Terraform code is being executed."
}

output "cluster_0_openshift_api_url" {
  value       = module.rosa_cluster_0.openshift_api_url
  description = "The endpoint URL for accessing the OpenShift API. This endpoint is used to interact with the OpenShift cluster's API server."
}

output "cluster_0_cluster_console_url" {
  value       = module.rosa_cluster_0.cluster_console_url
  description = "The URL endpoint for accessing the OpenShift web console. This endpoint provides a web-based user interface for managing the OpenShift cluster."
}

output "rosa_cluster_0_admin_password" {
  description = "ROSA cluster 0 admin password"
  value       = local.rosa_cluster_0_admin_password
  sensitive   = true
}
