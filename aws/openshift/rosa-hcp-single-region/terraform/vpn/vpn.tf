module "vpn" {
  source = "../../../../modules/vpn"

  vpn_name         = "my-vpn"
  client_key_names = ["my-client"]

  # The bucket will be used to store the configuration of the VPN clients and certificates
  s3_bucket_name  = "bucket-storing-vpn-keys"
  s3_ca_directory = "key/storing/certificates/"

  # TODO: in the doc, explains that this VPN is split by default

  vpc_id                  = var.vpc_id
  vpc_subnet_ids          = data.aws_subnets.private_subnets.ids
  vpc_target_network_cidr = data.aws_vpc.target.cidr_block
  providers = {
    aws.vpn    = aws
    aws.bucket = aws.aws_bucket_provider
  }
}

data "aws_vpc" "target" {
  id = var.vpc_id
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.target.id]
  }

  filter {
    name   = "tag:Name"
    values = ["*-subnet-private*"]
  }
}
variable "vpc_id" {
  description = "The ID of the VPC where the VPN will be created"
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
