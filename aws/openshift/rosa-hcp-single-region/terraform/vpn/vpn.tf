module "vpn" {
  source = "../../../../modules/vpn"

  vpn_name         = "my-vpn"
  client_key_names = ["my-client"]

  # The bucket will be used to store the configuration of the VPN clients and certificates
  s3_bucket_name  = "bucket-storing-vpn-keys"
  s3_ca_directory = "key/storing/certificates/"

  # TODO: in the doc, explains that this VPN is split by default

  vpc_subnet_ids          = var.vpc_subnet_ids
  vpc_id                  = var.vpc_id
  vpc_target_network_cidr = var.vpc_target_network_cidr

  providers = {
    aws.vpn    = aws
    aws.bucket = aws.aws_bucket_provider
  }
}

variable "vpc_subnet_ids" {
  description = "List of subnet IDs in the VPC to attach the VPN"
  type        = list(string)
  nullable    = false
}

variable "vpc_id" {
  description = "The ID of the VPC where the VPN will be created"
  type        = string
  nullable    = false
}

variable "vpc_target_network_cidr" {
  description = "CIDR block of the target network within the VPC"
  type        = string
  nullable    = false
}


output "vpn_endpoint" {
  description = "Endpoint of the VPN"
  value       = module.vpn.vpn_endpoint
}

output "vpn_client_configs_s3_urls" {
  description = "Map of S3 URLs of each VPN client config (client's name is the key)"
  value       = module.vpn.vpn_client_configs
}
