################################
# VPC Peering (cross-region)  #
################################

# Request a cross-region VPC peering connection from region 0 to region 1.
# Both VPCs are in the same AWS account. The `peer_region` argument enables
# inter-region VPC peering without requiring a Transit Gateway.
resource "aws_vpc_peering_connection" "owner_to_accepter" {
  vpc_id      = module.vpc_region_0.vpc_id
  peer_vpc_id = module.vpc_region_1.vpc_id
  peer_region = local.accepter.region

  tags = {
    Name = "${local.prefix}-vpc-peering"
  }
}

# Accept the peering request from region 1 provider.
# auto_accept = true works because both VPCs are in the same AWS account.
resource "aws_vpc_peering_connection_accepter" "accepter" {
  provider = aws.accepter

  vpc_peering_connection_id = aws_vpc_peering_connection.owner_to_accepter.id
  auto_accept               = true

  tags = {
    Name = "${local.prefix}-vpc-peering-accepter"
  }
}

################################
# VPC Route Tables            #
################################

# Region 0: route traffic destined for region 1 CIDR through the peering connection.
resource "aws_route" "region_0_private_to_region_1" {
  count = length(module.vpc_region_0.private_route_table_ids)

  route_table_id            = module.vpc_region_0.private_route_table_ids[count.index]
  destination_cidr_block    = local.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner_to_accepter.id

  depends_on = [aws_vpc_peering_connection_accepter.accepter]
}

# Region 1: route traffic destined for region 0 CIDR through the peering connection.
resource "aws_route" "region_1_private_to_region_0" {
  count    = length(module.vpc_region_1.private_route_table_ids)
  provider = aws.accepter

  route_table_id            = module.vpc_region_1.private_route_table_ids[count.index]
  destination_cidr_block    = local.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner_to_accepter.id

  depends_on = [aws_vpc_peering_connection_accepter.accepter]
}
