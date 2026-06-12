################################
# Transit Gateway (owner)     #
################################

resource "aws_ec2_transit_gateway" "owner" {
  provider = aws.owner

  description = "Transit Gateway for ${var.prefix} dual-region ECS"

  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = {
    Name = "${var.prefix}-tgw"
  }
}

################################
# Transit Gateway (accepter)  #
################################

resource "aws_ec2_transit_gateway" "accepter" {
  provider = aws.accepter

  description = "Transit Gateway for ${var.prefix} dual-region ECS (accepter)"

  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = {
    Name = "${var.prefix}-tgw-accepter"
  }
}

################################
# TGW Peering (cross-region)  #
################################

data "aws_region" "accepter" {
  provider = aws.accepter
}

resource "aws_ec2_transit_gateway_peering_attachment" "owner_to_accepter" {
  provider = aws.owner

  transit_gateway_id      = aws_ec2_transit_gateway.owner.id
  peer_transit_gateway_id = aws_ec2_transit_gateway.accepter.id
  peer_region             = data.aws_region.accepter.id

  tags = {
    Name = "${var.prefix}-tgw-peering"
  }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "accepter" {
  provider = aws.accepter

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.owner_to_accepter.id

  tags = {
    Name = "${var.prefix}-tgw-peering-accepter"
  }
}
