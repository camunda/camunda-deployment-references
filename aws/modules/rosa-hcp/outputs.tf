output "public_subnet_ids" {
  value       = join(",", module.vpc.public_subnets)
  description = "A comma-separated list of public subnet IDs in the VPC. These subnets are typically used for resources that require internet access."
}

output "private_subnet_ids" {
  value       = join(",", module.vpc.private_subnets)
  description = "A comma-separated list of private subnet IDs in the VPC. These subnets are typically used for internal resources that do not require direct internet access."
}

output "all_subnets" {
  value       = join(",", concat(module.vpc.private_subnets, module.vpc.public_subnets))
  description = "A comma-separated list of all subnet IDs (both public and private) in the VPC. This list can be used with the '--subnet-ids' parameter in ROSA commands for configuring cluster networking."
}

output "cluster_id" {
  value       = module.rosa_hcp.cluster_id
  description = "The unique identifier of the OpenShift cluster created on Red Hat OpenShift Service on AWS (ROSA). This ID is used to reference the cluster in subsequent operations."
}

output "openshift_api_url" {
  value       = module.rosa_hcp.cluster_api_url
  description = "The URL endpoint for accessing the OpenShift API. This endpoint is used to interact with the OpenShift cluster's API server."
}

output "cluster_console_url" {
  value       = module.rosa_hcp.cluster_console_url
  description = "The URL endpoint for accessing the OpenShift web console. This endpoint provides a web-based user interface for managing the OpenShift cluster."
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "The ID of the Virtual Private Cloud (VPC) where the OpenShift cluster and related resources are deployed."
}

output "vpc_availability_zones" {
  value       = module.vpc.availability_zones
  description = "The availability zones in which the VPC is located. This provides information about the distribution of resources across different physical locations within the AWS region."
}

output "aws_caller_identity_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "The AWS account ID of the caller. This is the account under which the Terraform code is being executed."
}

output "oidc_provider_id" {
  value       = module.rosa_hcp.oidc_config_id
  description = "OIDC provider for the OpenShift ROSA cluster. Allows to add additional IRSA mappings."
}
