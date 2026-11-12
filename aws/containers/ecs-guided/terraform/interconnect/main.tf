# Interconnect: the link between the VPCs of two regions, and nothing else. It only adds
# a peering connection, routes in the private route tables, and DNS forwarding. It does
# not touch the VPCs themselves, so it works the same on a VPC you brought.
#
# Each resource names its region, so one provider and one state cover both sides.
#
# Transit gateway is the alternative to peering for three or more regions. It is not
# part of this proof of concept; the dual-region reference has an implementation.

resource "terraform_data" "validate" {
  lifecycle {
    precondition {
      condition     = var.region_a != var.region_b
      error_message = "region_a and region_b must differ."
    }
    precondition {
      condition     = var.vpc_cidr_a != var.vpc_cidr_b
      error_message = "The two VPCs must not use the same CIDR block."
    }
    precondition {
      condition     = !var.enable_dns_resolver || (var.service_discovery_domain_a != "" && var.service_discovery_domain_b != "")
      error_message = "enable_dns_resolver requires service_discovery_domain_a and service_discovery_domain_b."
    }
    precondition {
      condition     = length(var.private_subnet_ids_a) >= 2 && length(var.private_subnet_ids_b) >= 2
      error_message = "Each region needs at least two private subnets for the resolver endpoints."
    }
  }
}

################################################################
#                       VPC peering                            #
################################################################

resource "aws_vpc_peering_connection" "this" {
  region = var.region_a

  vpc_id      = var.vpc_id_a
  peer_vpc_id = var.vpc_id_b
  peer_region = var.region_b
  auto_accept = false

  tags = {
    Name = "${var.prefix}-peering"
  }

  depends_on = [terraform_data.validate]
}

resource "aws_vpc_peering_connection_accepter" "this" {
  region = var.region_b

  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
  auto_accept               = true

  tags = {
    Name = "${var.prefix}-peering"
  }
}

resource "aws_vpc_peering_connection_options" "a" {
  region = var.region_a

  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

resource "aws_vpc_peering_connection_options" "b" {
  region = var.region_b

  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

resource "aws_route" "a_to_b" {
  for_each = toset(var.private_route_table_ids_a)

  region                    = var.region_a
  route_table_id            = each.value
  destination_cidr_block    = var.vpc_cidr_b
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

resource "aws_route" "b_to_a" {
  for_each = toset(var.private_route_table_ids_b)

  region                    = var.region_b
  route_table_id            = each.value
  destination_cidr_block    = var.vpc_cidr_a
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}
