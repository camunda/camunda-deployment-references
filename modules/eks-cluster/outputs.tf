output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

################################################################################
# Security Group
################################################################################

output "cluster_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster. Managed node groups use this security group for control-plane-to-data-plane communication. Referred to as 'Cluster security group' in the EKS console"
  value       = module.eks.cluster_security_group_id
}

output "cluster_security_group_arn" {
  description = "Amazon Resource Name (ARN) of the cluster security group"
  value       = module.eks.cluster_security_group_arn
}

output "cluster_primary_security_group_id" {
  description = "Cluster primary security group that was created by Amazon EKS for the cluster. Managed node groups use this security group for control-plane-to-data-plane communication. Referred to as 'Cluster security group' in the EKS console"
  value       = module.eks.cluster_primary_security_group_id

}

################################################################################
# IAM Role
################################################################################

output "cluster_iam_role_name" {
  description = "IAM role name of the EKS cluster"
  value       = module.eks.cluster_iam_role_name
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "access_entries" {
  description = "Map of access entries created and their attributes"
  value       = module.eks.access_entries
}

output "cluster_arn" {
  description = "ARN of the cluster"
  value       = module.eks.cluster_arn
}

################################################################################
# IRSA
################################################################################

# The following outputs are role arns that are required for the IAM to SA mapping
# Usage: Copy the output value and assign it as an annotation to a SA for usage
# example:
# eks.amazonaws.com/role-arn: arn:aws:iam::831074465991:role/irsa-${RANDOM}
# This allows the SA, if mapping was defined properly, to impersonate the role

output "cert_manager_arn" {
  value       = module.cert_manager_role.iam_role_arn
  description = "Amazon Resource Name of the cert-manager IAM role used for IAM Roles to Service Accounts mappings"
}

output "ebs_cs_arn" {
  value       = module.ebs_cs_role.iam_role_arn
  description = "Amazon Resource Name of the ebs-csi IAM role used for IAM Roles to Service Accounts mappings"
}

output "external_dns_arn" {
  value       = module.external_dns_role.iam_role_arn
  description = "Amazon Resource Name of the external-dns IAM role used for IAM Roles to Service Accounts mappings"
}

output "oidc_provider_arn" {
  value       = module.eks.oidc_provider_arn
  description = "Amazon Resource Name of the OIDC provider for the EKS cluster. Allows to add additional IRSA mappings"
}

output "aws_caller_identity_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "Account ID of the current AWS account"
}

output "oidc_provider_id" {
  value       = replace(module.eks.oidc_provider_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/", "")
  description = "OIDC provider for the EKS cluster. Allows to add additional IRSA mappings"
}

################################################################################
# VPC
################################################################################

output "vpc_id" {
  description = "VPC id of the cluster"
  value       = module.vpc.vpc_id
}

output "vpc_azs" {
  description = "VPC AZs of the cluster"
  value       = module.vpc.azs
}

output "private_vpc_cidr_blocks" {
  value       = module.vpc.private_subnets_cidr_blocks
  description = "Private VPC CIDR blocks"
}

output "public_vpc_cidr_blocks" {
  value       = module.vpc.public_subnets_cidr_blocks
  description = "Public VPC CIDR blocks"
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnets
  description = "Private subnet IDs"
}

output "default_security_group_id" {
  value       = module.vpc.default_security_group_id
  description = "The ID of the security group created by default on VPC creation"
}

output "vpc_main_route_table_id" {
  value       = module.vpc.vpc_main_route_table_id
  description = "The ID of the main route table associated with this VPC"
}

output "private_route_table_ids" {
  value       = module.vpc.private_route_table_ids
  description = "The IDs of the private route tables associated with this VPC"
}
