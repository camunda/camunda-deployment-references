locals {
  rosa_cluster_name = "my-rosa" # Change this to a name of your choice

  rosa_cluster_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c", ]

  rosa_rh_token = "REPLACEME" # Change the token with yours

  rosa_admin_username = "kubeadmin"
  rosa_admin_password = "CHANGEME1234r!" # Change the password of your admin password
}

module "rosa_cluster" {
  source = "git::https://github.com/camunda/camunda-tf-rosa//modules/rosa-hcp?ref=feature/official-doc-integ"

  cluster_name = local.rosa_cluster_name

  availability_zones = local.rosa_cluster_zones

  # Set CIDR ranges or use the defaults
  vpc_cidr_block     = "10.0.0.0/16"
  machine_cidr_block = "10.0.0.0/18"
  service_cidr_block = "10.0.128.0/18"
  pod_cidr_block     = "10.0.64.0/18"

  offline_access_token = local.rosa_rh_token

  # admin access
  htpasswd_username = local.rosa_admin_username
  htpasswd_password = local.rosa_admin_password

  # Default node type for the OpenShift cluster
  compute_node_instance_type = "m6i.xlarge"
  replicas                   = 3
}

# Outputs of the parent module

output "public_subnet_ids" {
  value       = module.rosa_cluster.public_subnet_ids
  description = "A comma-separated list of public subnet IDs in the VPC. These subnets are typically used for resources that require internet access."
}

output "private_subnet_ids" {
  value       = module.rosa_cluster.private_subnet_ids
  description = "A comma-separated list of private subnet IDs in the VPC. These subnets are typically used for internal resources that do not require direct internet access."
}

output "cluster_id" {
  value       = module.rosa_cluster.cluster_id
  description = "The unique identifier of the OpenShift cluster created on Red Hat OpenShift Service on AWS (ROSA). This ID is used to reference the cluster in subsequent operations."
}

output "oidc_provider_id" {
  value       = module.rosa_cluster.oidc_provider_id
  description = "OIDC provider for the ROSA cluster. Allows adding additional IAM Role for Service Accounts (IRSA) mappings."
}

output "aws_caller_identity_account_id" {
  value       = module.rosa_cluster.aws_caller_identity_account_id
  description = "The AWS account ID of the caller. This is the account under which the Terraform code is being executed."
}

output "openshift_api_url" {
  value       = module.rosa_cluster.openshift_api_url
  description = "The endpoint URL for accessing the OpenShift API. This endpoint is used to interact with the OpenShift cluster's API server."
}

output "cluster_console_url" {
  value       = module.rosa_cluster.cluster_console_url
  description = "The URL endpoint for accessing the OpenShift web console. This endpoint provides a web-based user interface for managing the OpenShift cluster."
}