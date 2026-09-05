###############################################################################
# Transit Gateway inter-region peering (one pair of regions)                  #
#                                                                             #
# Transit Gateway peering is point-to-point and NOT transitive: a packet       #
# cannot hop through an intermediate TGW. An N-region topology therefore       #
# requires a full mesh of N*(N-1)/2 peerings. This module represents exactly   #
# one edge of that mesh.                                                      #
#                                                                             #
# Peering attachments never propagate routes, so static routes are added on    #
# both TGW route tables.                                                      #
###############################################################################

data "aws_region" "accepter" {
  provider = aws.accepter
}

resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  provider = aws.owner

  transit_gateway_id      = var.owner_transit_gateway_id
  peer_transit_gateway_id = var.accepter_transit_gateway_id
  peer_region             = data.aws_region.accepter.region

  tags = {
    Name = "${var.name}-tgw-peering"
  }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  provider = aws.accepter

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.this.id

  tags = {
    Name = "${var.name}-tgw-peering-accepter"
  }
}

###############################################################################
# Static routes on both Transit Gateway route tables                          #
###############################################################################

resource "aws_ec2_transit_gateway_route" "owner_to_accepter" {
  provider = aws.owner

  for_each = toset(var.accepter_cidr_blocks)

  destination_cidr_block         = each.value
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this.id
  transit_gateway_route_table_id = var.owner_transit_gateway_route_table_id

  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.this]
}

resource "aws_ec2_transit_gateway_route" "accepter_to_owner" {
  provider = aws.accepter

  for_each = toset(var.owner_cidr_blocks)

  destination_cidr_block         = each.value
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.this.transit_gateway_attachment_id
  transit_gateway_route_table_id = var.accepter_transit_gateway_route_table_id

  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.this]
}
