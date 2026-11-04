# Network layer. Use it to create a VPC, or set byo_vpc = true to pass the IDs of an
# existing one: every other layer reads the same outputs either way.

module "network" {
  source = "../../../../modules/network"

  name                    = var.prefix
  byo_vpc                 = var.byo_vpc
  cidr                    = var.cidr
  az_count                = var.az_count
  single_nat_gateway      = var.single_nat_gateway
  vpc_id                  = var.vpc_id
  vpc_cidr                = var.vpc_cidr
  private_subnet_ids      = var.private_subnet_ids
  public_subnet_ids       = var.public_subnet_ids
  private_route_table_ids = var.private_route_table_ids
}
