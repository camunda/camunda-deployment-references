################################
# Transit Gateway             #
################################

# Transit Gateway in region 0 (owner)
resource "aws_ec2_transit_gateway" "this" {
  description = "Transit Gateway for ${local.prefix} dual-region ECS"

  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = {
    Name = "${local.prefix}-tgw"
  }
}

################################
# TGW Peering (cross-region)  #
################################

# Create a peering attachment from region 0 TGW to region 1
resource "aws_ec2_transit_gateway" "accepter" {
  provider = aws.accepter

  description = "Transit Gateway for ${local.prefix} dual-region ECS (accepter)"

  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = {
    Name = "${local.prefix}-tgw-accepter"
  }
}

resource "aws_ec2_transit_gateway_peering_attachment" "owner_to_accepter" {
  transit_gateway_id      = aws_ec2_transit_gateway.this.id
  peer_transit_gateway_id = aws_ec2_transit_gateway.accepter.id
  peer_region             = local.accepter.region

  tags = {
    Name = "${local.prefix}-tgw-peering"
  }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "accepter" {
  provider = aws.accepter

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.owner_to_accepter.id

  tags = {
    Name = "${local.prefix}-tgw-peering-accepter"
  }
}

################################
# VPC Attachments             #
################################

# Attach region 0 VPC to region 0 TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "region_0" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.vpc_region_0.vpc_id
  subnet_ids         = module.vpc_region_0.private_subnets

  dns_support = "enable"

  tags = {
    Name = "${local.prefix_region_0}-tgw-attachment"
  }
}

# Attach region 1 VPC to region 1 TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "region_1" {
  provider = aws.accepter

  transit_gateway_id = aws_ec2_transit_gateway.accepter.id
  vpc_id             = module.vpc_region_1.vpc_id
  subnet_ids         = module.vpc_region_1.private_subnets

  dns_support = "enable"

  tags = {
    Name = "${local.prefix_region_1}-tgw-attachment"
  }
}

################################
# TGW Route Tables            #
################################

# Route from region 0 TGW to region 1 VPC CIDR via peering
resource "aws_ec2_transit_gateway_route" "region_0_to_region_1" {
  destination_cidr_block         = local.accepter.vpc_cidr_block
  transit_gateway_route_table_id = aws_ec2_transit_gateway.this.association_default_route_table_id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.owner_to_accepter.id

  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.accepter]
}

# Route from region 1 TGW to region 0 VPC CIDR via peering
resource "aws_ec2_transit_gateway_route" "region_1_to_region_0" {
  provider = aws.accepter

  destination_cidr_block         = local.owner.vpc_cidr_block
  transit_gateway_route_table_id = aws_ec2_transit_gateway.accepter.association_default_route_table_id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.accepter.id
}

################################
# VPC Route Tables            #
################################

# Region 0: route to region 1 CIDR via TGW
resource "aws_route" "region_0_private_to_region_1" {
  count = length(module.vpc_region_0.private_route_table_ids)

  route_table_id         = module.vpc_region_0.private_route_table_ids[count.index]
  destination_cidr_block = local.accepter.vpc_cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.region_0]
}

# Region 1: route to region 0 CIDR via TGW
resource "aws_route" "region_1_private_to_region_0" {
  count    = length(module.vpc_region_1.private_route_table_ids)
  provider = aws.accepter

  route_table_id         = module.vpc_region_1.private_route_table_ids[count.index]
  destination_cidr_block = local.owner.vpc_cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.accepter.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.region_1]
}
