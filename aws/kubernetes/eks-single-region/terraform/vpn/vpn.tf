module "vpn" {
  source = "../../../../modules/vpn"

  vpn_name         = "my-vpn"
  client_key_names = ["my-client"]

  vpc_id                  = var.vpc_id
  vpc_subnet_ids          = data.aws_subnets.private_subnets.ids
  vpc_target_network_cidr = data.aws_vpc.target.cidr_block

  # restrict the vpn to be accessed from a list of ip, by default allow all sources
  vpn_allowed_cidr_blocks = ["0.0.0.0/0"]
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
    values = ["*-private*"]
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

output "vpn_client_configs" {
  description = "Map of each VPN client config (client's name is the key)"
  value       = module.vpn.vpn_configs
  sensitive   = true
}
