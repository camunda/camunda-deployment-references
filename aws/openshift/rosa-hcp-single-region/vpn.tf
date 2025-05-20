# If your cluster is private, you will need a VPN to access it
locals {
  create_vpn = module.rosa_cluster.private ? true : false
}
module "vpn" {
  count = local.create_vpn ? 1 : 0

  source = "../../modules/vpn"

  s3_bucket_name          = "bucket-storing-vpn-keys"
  s3_bucket_region        = "eu-central-1"
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
