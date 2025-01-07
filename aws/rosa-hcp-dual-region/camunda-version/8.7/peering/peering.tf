################################
# Peering Connection          #
################################
# This is the peering connection between the two VPCs
# You always have a requester and an accepter. The requester is the one who initiates the connection.
# That's why were using the owner and accepter naming convention.
# Auto_accept is only required in the accepter. Otherwise you have to manually accept the connection.
# Auto_accept only works in the "owner" if the VPCs are in the same region


resource "aws_vpc_peering_connection" "owner" {
  vpc_id      = var.owner.vpc_id
  peer_vpc_id = var.accepter.vpc_id
  peer_region = var.accepter.region
  auto_accept = false

  tags = {
    Name = var.cluster_set_name
  }
}

resource "aws_vpc_peering_connection_accepter" "accepter" {
  provider = aws.accepter

  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
  auto_accept               = true

  tags = {
    Name = var.cluster_set_name
  }
}


################################
# Route Table Updates          #
################################
# These are required to let the VPC know where to route the traffic to
# In this case non local cidr range --> VPC Peering connection.

resource "aws_route" "owner" {
  route_table_id            = var.owner.public_route_table_id
  destination_cidr_block    = var.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}

resource "aws_route" "owner_private" {
  for_each       = var.owner.private_route_table_ids
  route_table_id = each.value

  destination_cidr_block    = var.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}

resource "aws_route" "accepter" {
  provider = aws.accepter

  route_table_id            = var.accepter.public_route_table_id
  destination_cidr_block    = var.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}

resource "aws_route" "accepter_private" {
  provider = aws.accepter

  for_each       = var.accepter.private_route_table_ids
  route_table_id = each.value

  destination_cidr_block    = var.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.owner.id
}

################################
# Security Groups Updates      #
################################
# These changes are required to actually allow inbound traffic from the other VPC.

resource "aws_vpc_security_group_ingress_rule" "owner_eks_primary" {
  security_group_id = var.owner.security_group_id

  cidr_ipv4   = var.accepter.vpc_cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1
}

resource "aws_vpc_security_group_ingress_rule" "accepter_eks_primary" {
  provider = aws.accepter

  security_group_id = var.accepter.security_group_id

  cidr_ipv4   = var.owner.vpc_cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1
}
