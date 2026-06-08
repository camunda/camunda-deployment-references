################################################################
#               VPC Peering (alternative to Transit Gateway)    #
################################################################

# Requester (region 0) creates the peering connection
resource "aws_vpc_peering_connection" "cross_region" {
  count = var.networking_mode == "vpc_peering" ? 1 : 0

  vpc_id      = module.vpc_region_0.vpc_id
  peer_vpc_id = module.vpc_region_1.vpc_id
  peer_region = var.region_1
  auto_accept = false

  tags = {
    Name = "${local.prefix}-vpc-peering"
  }
}

# Accepter (region 1) accepts the peering connection
resource "aws_vpc_peering_connection_accepter" "cross_region" {
  count    = var.networking_mode == "vpc_peering" ? 1 : 0
  provider = aws.accepter

  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id
  auto_accept               = true

  tags = {
    Name = "${local.prefix}-vpc-peering"
  }
}

# Enable DNS resolution on requester side
resource "aws_vpc_peering_connection_options" "requester" {
  count = var.networking_mode == "vpc_peering" ? 1 : 0

  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.cross_region]
}

# Enable DNS resolution on accepter side
resource "aws_vpc_peering_connection_options" "accepter" {
  count    = var.networking_mode == "vpc_peering" ? 1 : 0
  provider = aws.accepter

  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.cross_region]
}

################################
# VPC Route Tables (Peering)  #
################################

# Region 0: route to region 1 CIDR via peering
resource "aws_route" "region_0_private_to_region_1_peering" {
  count = var.networking_mode == "vpc_peering" ? length(module.vpc_region_0.private_route_table_ids) : 0

  route_table_id            = module.vpc_region_0.private_route_table_ids[count.index]
  destination_cidr_block    = local.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id
}

# Region 1: route to region 0 CIDR via peering
resource "aws_route" "region_1_private_to_region_0_peering" {
  count    = var.networking_mode == "vpc_peering" ? length(module.vpc_region_1.private_route_table_ids) : 0
  provider = aws.accepter

  route_table_id            = module.vpc_region_1.private_route_table_ids[count.index]
  destination_cidr_block    = local.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[0].id
}
