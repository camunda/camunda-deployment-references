locals {
  # Enable the VPN is your cluster is private
  enable_vpn = local.rosa_private_cluster ? true : false
}
module "vpn" {
  count = local.enable_vpn ? 1 : 0

  source = "../../modules/vpn"

  s3_bucket_name          = "bucket-storing-vpn-keys"
  vpc_subnet_ids          = split(",", module.rosa_cluster.private_subnet_ids)
  vpc_id                  = module.rosa_cluster.vpc_id
  vpc_target_network_cidr = module.rosa_cluster.vpc_cidr_block

  client_key_names = ["my-client"]
  vpn_name         = "${local.rosa_cluster_name}-vpn"

  providers = {
    aws        = aws
    aws-bucket = aws.aws_bucket_provider
  }
}

output "vpn_endpoint" {
  description = "Endpoint of the VPN"
  value       = length(module.vpn) > 0 ? module.vpn[0].vpn_endpoint : ""
}

output "vpn_client_keys_s3_urls" {
  description = "Map of S3 URLs for client private and public keys"
  value       = length(module.vpn) > 0 ? module.vpn[0].vpn_client_keys_s3_urls : ""
}
