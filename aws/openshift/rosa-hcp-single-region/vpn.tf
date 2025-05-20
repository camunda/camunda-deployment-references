locals {
  # Enable the VPN is your cluster is private
  enable_vpn = local.rosa_private_cluster ? true : false
}
module "vpn" {
  count = local.enable_vpn ? 1 : 0

  source = "../../modules/vpn"

  s3_bucket_name          = "bucket-storing-vpn-keys"
  vpc_subnet_ids          = module.rosa_cluster.private_subnet_ids
  vpc_id                  = module.rosa_cluster.vpc_id
  vpc_target_network_cidr = module.rosa_cluster.vpc_cidr_block

  vpn_name         = "${local.rosa_cluster_name}-vpn"
  client_key_names = ["my-client"]
}

output "vpn_endpoint" {
  description = "Endpoint of the VPN"
  value       = module.vpn[0].vpn_endpoint
}

output "vpn_client_keys_s3_urls" {
  description = "Map of S3 URLs for client private and public keys"
  value       = module.vpn[0].vpn_client_keys_s3_urls
}
