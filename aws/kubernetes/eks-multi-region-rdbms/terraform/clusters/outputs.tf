################################################################################
# Outputs                                                                      #
#                                                                              #
# Everything downstream (the database root module, the procedure scripts and    #
# the integration tests) consumes region-indexed maps rather than               #
# `region_0_*` scalars, so adding a region does not rename an output.           #
################################################################################

output "region_slot_count" {
  description = <<-EOT
    Number of region slots. Feeds `global.multiregion.regions` in the Camunda
    Helm values and therefore the Zeebe broker node ID stride. Immutable for
    the lifetime of the Camunda cluster.
  EOT
  value       = local.region_slot_count
}

output "active_region_count" {
  description = "Number of region slots currently deployed"
  value       = var.active_region_count
}

output "regions" {
  description = "Region slot definitions, indexed by slot number"
  value       = { for i in local.active_indices : i => var.regions[i] }
}

output "cluster_names" {
  description = "EKS cluster name per region slot"
  value       = { for i in local.active_indices : i => "${var.cluster_name}-${var.regions[i].short_name}" }
}

output "vpc_ids" {
  description = "VPC ID per region slot"
  value       = { for i, c in local.clusters : i => c.vpc_id }
}

output "private_subnet_ids" {
  description = "Private subnet IDs per region slot, used by the database root module"
  value       = { for i, c in local.clusters : i => c.private_subnet_ids }
}

output "vpc_cidr_blocks" {
  description = "VPC CIDR block per region slot"
  value       = { for i in local.active_indices : i => var.regions[i].vpc_cidr_block }
}

output "service_cidr_blocks" {
  description = "Kubernetes service CIDR block per region slot"
  value       = { for i in local.active_indices : i => var.regions[i].service_cidr_block }
}

output "pod_cidr_blocks" {
  description = <<-EOT
    Pod CIDR block per region slot, i.e. the VPC secondary CIDR carrying the
    custom networking subnets.

    This is what `subctl join --clustercidr` must be given: passing the VPC
    CIDR instead makes Submariner claim the whole routed range and collide with
    the Transit Gateway. See pod-networking.tf.
  EOT
  value       = { for i in local.active_indices : i => var.regions[i].pod_cidr_block }
}

output "pod_subnet_ids" {
  description = "Custom networking subnet IDs per region slot, one per availability zone, referenced by the ENIConfig objects"
  value       = local.pod_subnet_ids
}

output "oidc_provider_arns" {
  description = "OIDC provider ARN per region slot, used to bind IRSA roles"
  value       = { for i, c in local.clusters : i => c.oidc_provider_arn }
}

output "transit_gateway_ids" {
  description = "Transit Gateway ID per region slot"
  value       = { for i, h in local.tgw_hubs : i => h.transit_gateway_id }
}

output "all_cidr_blocks" {
  description = "Every VPC, Kubernetes service and pod CIDR of the active regions, used to build database firewall rules"
  value       = concat(local.active_vpc_cidr_blocks, local.active_svc_cidr_blocks, local.active_pod_cidr_blocks)
}

################################
# Secondary storage            #
################################

output "database_global_cluster_id" {
  description = "Identifier of the Aurora Global Database, consumed by the failover and failback procedures"
  value       = one(aws_rds_global_cluster.camunda[*].id)
}

output "database_writer_endpoint" {
  description = "Writer endpoint of the current Aurora Global Database primary"
  value       = local.database_writer_endpoint
}

output "database_cluster_identifiers" {
  description = "Aurora cluster identifier per region slot hosting a database member"
  value       = { for i, m in local.database_members : i => m.cluster_identifier }
}

output "database_name" {
  description = "Name of the database backing the Camunda secondary storage"
  value       = var.database_name
}

output "database_username" {
  description = "Master username of the Aurora Global Database"
  value       = var.database_username
  sensitive   = true
}

output "database_password" {
  description = "Master password of the Aurora Global Database"
  value       = one(random_password.database[*].result)
  sensitive   = true
}

output "camunda_rdbms_url" {
  description = <<-EOT
    JDBC URL for `orchestration.data.secondaryStorage.rdbms.url`.

    It uses the AWS Advanced JDBC Wrapper with the `failover` plugin and the
    instance host patterns of every Aurora Global member, so that a global
    failover is followed transparently and Camunda never has to be
    reconfigured. Replace this URL with any single-writer endpoint to run the
    same architecture on a different database.
  EOT
  value = local.database_enabled ? format(
    "jdbc:aws-wrapper:postgresql://%s:5432/%s?wrapperPlugins=%sfailover&globalClusterInstanceHostPatterns=%s",
    local.database_writer_endpoint,
    var.database_name,
    var.database_iam_auth_enabled ? "iam," : "",
    local.database_host_patterns,
  ) : null
}
