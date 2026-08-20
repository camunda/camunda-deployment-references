###############################################################################
# Transit Gateway hub for a single region                                     #
#                                                                             #
# One instance of this module is created per participating region. It owns:   #
#   * the regional Transit Gateway                                            #
#   * the VPC attachment of the local EKS VPC                                 #
#   * the VPC route table entries pointing remote CIDRs at the local TGW      #
#                                                                             #
# Cross-region wiring (TGW <-> TGW peering) is handled by the companion       #
# module `transit-gateway-peering`, which needs two provider aliases and is    #
# therefore kept separate. Splitting the two lets a caller scale the mesh by   #
# instantiating N hubs and N*(N-1)/2 peerings instead of duplicating a         #
# hardcoded two-region module.                                                #
###############################################################################

resource "aws_ec2_transit_gateway" "this" {
  description = "Transit Gateway for ${var.name}"

  # Peering attachments are associated with the default route table but never
  # propagate routes, so static routes are added by the peering module.
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = {
    Name = "${var.name}-tgw"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids

  # Appliance mode is not needed: traffic is symmetric and stateless from the
  # TGW point of view. DNS support lets Route 53 resolution traverse the TGW.
  dns_support = "enable"

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = {
    Name = "${var.name}-tgw-attachment"
  }
}

###############################################################################
# VPC route table entries: every remote CIDR is reachable through the TGW      #
###############################################################################

locals {
  # Cartesian product of route tables x remote CIDRs.
  #
  # The keys are built from the route table INDEX rather than its ID: the IDs
  # are only known after apply, and Terraform requires for_each keys to be
  # known at plan time. The index is known, because the length of the route
  # table list is fixed by configuration even when the IDs are not.
  #
  # Keying by index also means adding a region appends entries instead of
  # renumbering existing ones, as long as the route table list is stable.
  vpc_routes = {
    for pair in setproduct(range(length(var.vpc_route_table_ids)), var.remote_cidr_blocks) :
    "${pair[0]}|${pair[1]}" => {
      route_table_index = pair[0]
      cidr_block        = pair[1]
    }
  }
}

resource "aws_route" "remote" {
  for_each = local.vpc_routes

  route_table_id         = var.vpc_route_table_ids[each.value.route_table_index]
  destination_cidr_block = each.value.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}
