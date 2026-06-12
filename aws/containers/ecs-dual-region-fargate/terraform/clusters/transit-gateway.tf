################################
# Transit Gateway             #
################################

module "transit_gateway" {
  count  = var.networking_mode == "transit_gateway" ? 1 : 0
  source = "../../../../modules/transit-gateway"

  providers = {
    aws.owner    = aws
    aws.accepter = aws.accepter
  }

  prefix = local.prefix
}

################################
# VPC Attachments             #
################################

# Attach region 0 VPC to region 0 TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "region_0" {
  count = var.networking_mode == "transit_gateway" ? 1 : 0

  transit_gateway_id = module.transit_gateway[0].owner_transit_gateway_id
  vpc_id             = module.vpc_region_0.vpc_id
  subnet_ids         = module.vpc_region_0.private_subnets

  dns_support = "enable"

  tags = {
    Name = "${local.prefix_region_0}-tgw-attachment"
  }
}

# Attach region 1 VPC to region 1 TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "region_1" {
  count    = var.networking_mode == "transit_gateway" ? 1 : 0
  provider = aws.accepter

  transit_gateway_id = module.transit_gateway[0].accepter_transit_gateway_id
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
  count = var.networking_mode == "transit_gateway" ? 1 : 0

  destination_cidr_block         = local.accepter.vpc_cidr_block
  transit_gateway_route_table_id = module.transit_gateway[0].owner_default_route_table_id
  transit_gateway_attachment_id  = module.transit_gateway[0].peering_attachment_id

  depends_on = [module.transit_gateway]
}

# Route from region 1 TGW to region 0 VPC CIDR via peering
resource "aws_ec2_transit_gateway_route" "region_1_to_region_0" {
  count    = var.networking_mode == "transit_gateway" ? 1 : 0
  provider = aws.accepter

  destination_cidr_block         = local.owner.vpc_cidr_block
  transit_gateway_route_table_id = module.transit_gateway[0].accepter_default_route_table_id
  transit_gateway_attachment_id  = module.transit_gateway[0].peering_accepter_attachment_id
}

################################
# VPC Route Tables            #
################################

# Region 0: route to region 1 CIDR via TGW
resource "aws_route" "region_0_private_to_region_1_tgw" {
  count = var.networking_mode == "transit_gateway" ? length(module.vpc_region_0.private_route_table_ids) : 0

  route_table_id         = module.vpc_region_0.private_route_table_ids[count.index]
  destination_cidr_block = local.accepter.vpc_cidr_block
  transit_gateway_id     = module.transit_gateway[0].owner_transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.region_0]
}

# Region 1: route to region 0 CIDR via TGW
resource "aws_route" "region_1_private_to_region_0_tgw" {
  count    = var.networking_mode == "transit_gateway" ? length(module.vpc_region_1.private_route_table_ids) : 0
  provider = aws.accepter

  route_table_id         = module.vpc_region_1.private_route_table_ids[count.index]
  destination_cidr_block = local.owner.vpc_cidr_block
  transit_gateway_id     = module.transit_gateway[0].accepter_transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.region_1]
}
