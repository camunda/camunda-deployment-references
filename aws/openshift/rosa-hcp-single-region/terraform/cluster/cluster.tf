locals {
  rosa_cluster_name = "my-rosa" # Change this to a name of your choice

  rosa_cluster_zones = ["eu-north-1a", "eu-north-1b", "eu-north-1c"] # Adjust to your needs and align with your value of AWS_REGION

  rosa_admin_username = "kubeadmin"
  rosa_admin_password = "CHANGEME1234r!" # Change the password of your admin password

  # Prevent the cluster to be accessed at all from the public Internet if true
  rosa_private_cluster = false
  rosa_tags            = {} # additional tags that you may want to apply to the resources
}

module "rosa_cluster" {
  source = "../../../../modules/rosa-hcp"

  cluster_name = local.rosa_cluster_name

  availability_zones = local.rosa_cluster_zones

  # Set CIDR ranges or use the defaults
  vpc_cidr_block     = "10.0.0.0/16"
  machine_cidr_block = "10.0.0.0/18"
  service_cidr_block = "10.0.128.0/18"
  pod_cidr_block     = "10.0.64.0/18"

  # admin access
  htpasswd_username = local.rosa_admin_username
  htpasswd_password = local.rosa_admin_password

  # Default node type for the OpenShift cluster
  compute_node_instance_type = "m7i.xlarge"
  replicas                   = 6

  private = local.rosa_private_cluster

  # renovate: datasource=custom.rosa-camunda depName=red-hat-openshift versioning=semver
  openshift_version = "4.20.3"

  tags = local.rosa_tags
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

output "vpc_id" {
  value       = module.rosa_cluster.vpc_id
  description = "The ID of the Virtual Private Cloud (VPC) where the OpenShift cluster and related resources are deployed."
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
