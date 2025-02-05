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
  cluster_set_name = "cl-${var.cluster_1_vpc_id}-${var.cluster_2_vpc_id}"
}

resource "aws_vpc_peering_connection" "cluster_1" {
  provider = aws.cluster_1

  vpc_id      = var.cluster_1_vpc_id
  peer_vpc_id = var.cluster_2_vpc_id
  peer_region = var.cluster_2_region
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

  route_table_id            = data.aws_route_tables.cluster_1_public_route_tables.ids[0]
  destination_cidr_block    = data.aws_vpc.cluster_2_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
}

resource "aws_route" "cluster_1_private" {
  provider = aws.cluster_1

  count          = length(data.aws_route_tables.cluster_1_private_route_tables.ids)
  route_table_id = data.aws_route_tables.cluster_1_private_route_tables.ids[count.index]

  destination_cidr_block    = data.aws_vpc.cluster_2_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
}

resource "aws_route" "cluster_2" {
  provider = aws.cluster_2

  route_table_id            = data.aws_route_tables.cluster_2_public_route_tables.ids[0]
  destination_cidr_block    = data.aws_vpc.cluster_1_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
}

resource "aws_route" "cluster_2_private" {
  provider = aws.cluster_2

  count          = length(data.aws_route_tables.cluster_2_private_route_tables.ids)
  route_table_id = data.aws_route_tables.cluster_2_private_route_tables.ids[count.index]


  destination_cidr_block    = data.aws_vpc.cluster_1_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.cluster_1.id
}

################################
# Security Groups Updates      #
################################
# These changes are required to actually allow inbound traffic from the other VPC.

resource "aws_vpc_security_group_ingress_rule" "cluster_1_primary" {
  provider = aws.cluster_1

  security_group_id = data.aws_security_groups.cluster_1_worker_sg.ids[0]

  cidr_ipv4   = data.aws_vpc.cluster_2_vpc.cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1

  description = "Allow Cluster 2 traffic (no restriction)"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_2_primary" {
  provider = aws.cluster_2

  security_group_id = data.aws_security_groups.cluster_2_worker_sg.ids[0]

  cidr_ipv4   = data.aws_vpc.cluster_1_vpc.cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1

  description = "Allow Cluster 1 traffic (no restriction)"
}

### Cluster 1 data retrieval
data "aws_vpc" "cluster_1_vpc" {
  provider = aws.cluster_1
  id       = var.cluster_1_vpc_id
}

# Filter the public route table (associated with an Internet Gateway)
data "aws_route_tables" "cluster_1_public_route_tables" {
  provider = aws.cluster_1
  filter {
    name   = "vpc-id"
    values = [var.cluster_1_vpc_id]
  }
  filter {
    name   = "route.gateway-id"
    values = ["igw-*"]
  }
}

# Get all private route tables (excluding the public one)
data "aws_route_tables" "cluster_1_private_route_tables" {
  provider = aws.cluster_1

  filter {
    name   = "vpc-id"
    values = [var.cluster_1_vpc_id]
  }

  filter {
    name   = "route.gateway-id"
    values = [""]
  }
}

# Retrieve the security group based on VPC ID and description
data "aws_security_groups" "cluster_1_worker_sg" {

  provider = aws.cluster_1
  filter {
    name   = "vpc-id"
    values = [var.cluster_1_vpc_id]
  }

  filter {
    name   = "description"
    values = ["default worker security group"]
  }
}


### Cluster 2 data retrieval
data "aws_vpc" "cluster_2_vpc" {
  provider = aws.cluster_2
  id       = var.cluster_2_vpc_id
}

data "aws_route_tables" "cluster_2_public_route_tables" {
  provider = aws.cluster_2

  filter {
    name   = "vpc-id"
    values = [var.cluster_2_vpc_id]
  }
  filter {
    name   = "route.gateway-id"
    values = ["igw-*"]
  }
}

# Get all private route tables (excluding the public one)
data "aws_route_tables" "cluster_2_private_route_tables" {
  provider = aws.cluster_2

  filter {
    name   = "vpc-id"
    values = [var.cluster_2_vpc_id]
  }

  filter {
    name   = "route.gateway-id"
    values = [""]
  }
}


# Retrieve the security group based on VPC ID and description
data "aws_security_groups" "cluster_2_worker_sg" {

  provider = aws.cluster_2
  filter {
    name   = "vpc-id"
    values = [var.cluster_2_vpc_id]
  }

  filter {
    name   = "description"
    values = ["default worker security group"]
  }
}
