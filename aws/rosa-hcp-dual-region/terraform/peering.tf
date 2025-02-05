################################
# Peering Connection          #
################################
# This is the peering connection between the two VPCs
# You always have a requester and an accepter. The requester is the one who initiates the connection.
# That's why were using the owner and accepter naming convention.
# cluster_1 is the owner
# cluster_2 is the accepter
# Auto_accept is only required in the accepter. Otherwise you have to manually accept the connection.
# Auto_accept only works in the "owner" if the VPCs are in the same region

locals {
  # Name of the cluster set
  cluster_set_name = "cl-${local.rosa_cluster_1_name}-${local.rosa_cluster_2_name}"
}

resource "aws_vpc_peering_connection" "cluster_1" {
  provider = aws.cluster_1

  vpc_id      = var.owner.vpc_id
  peer_vpc_id = var.accepter.vpc_id
  peer_region = var.accepter.region
  auto_accept = false

  tags = {
    Name = local.cluster_set_name
  }
}

resource "aws_vpc_peering_connection_accepter" "cluster_2" {
  provider = aws.cluster_2

  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
  auto_accept               = true

  tags = {
    Name = local.cluster_set_name
  }
}

resource "aws_vpc_peering_connection_options" "cluster_2" {
  provider = aws.cluster_2

  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.cluster_2]
}


################################
# Route Table Updates          #
################################
# These are required to let the VPC know where to route the traffic to
# In this case non local cidr range --> VPC Peering connection.

resource "aws_route" "cluster_1" {
  provider = aws.cluster_1

  route_table_id            = var.owner.public_route_table_id
  destination_cidr_block    = var.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
}

resource "aws_route" "cluster_1_private" {
  provider = aws.cluster_1

  for_each       = var.owner.private_route_table_ids
  route_table_id = each.value

  destination_cidr_block    = var.accepter.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
}

resource "aws_route" "accepter" {
  provider = aws.cluster_2

  route_table_id            = var.accepter.public_route_table_id
  destination_cidr_block    = var.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
}

resource "aws_route" "cluster_2_private" {
  provider = aws.cluster_2

  for_each       = var.accepter.private_route_table_ids
  route_table_id = each.value

  destination_cidr_block    = var.owner.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
}

################################
# Security Groups Updates      #
################################
# These changes are required to actually allow inbound traffic from the other VPC.

resource "aws_vpc_security_group_ingress_rule" "cluster_1_primary" {
  provider = aws.cluster_1

  security_group_id = var.owner.security_group_id

  cidr_ipv4   = var.accepter.vpc_cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1

  description = "Allow Cluster 2 traffic (no restriction)"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_2_primary" {
  provider = aws.cluster_2

  security_group_id = var.accepter.security_group_id

  cidr_ipv4   = var.owner.vpc_cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1

  description = "Allow Cluster 1 traffic (no restriction)"
}
