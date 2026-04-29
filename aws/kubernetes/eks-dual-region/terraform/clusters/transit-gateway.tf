################################
# Transit Gateway Attachment   #
################################
# These resources attach the two VPCs to an existing Transit Gateway.
# The Transit Gateway itself must be created outside this module.
# For cross-account TGW, provide the RAM share ARN.

locals {
  is_transit_gateway   = var.connectivity_type == "transit-gateway"
  is_tgw_cross_account = local.is_transit_gateway && var.transit_gateway_ram_share_arn != null
}

################################
# Cross-Account RAM Share      #
################################

data "aws_caller_identity" "current" {
  count = local.is_tgw_cross_account ? 1 : 0
}

resource "aws_ram_principal_association" "tgw" {
  count = local.is_tgw_cross_account ? 1 : 0

  resource_share_arn = var.transit_gateway_ram_share_arn
  principal          = data.aws_caller_identity.current[0].account_id
}

################################
# VPC Attachments              #
################################

resource "aws_ec2_transit_gateway_vpc_attachment" "region_0" {
  count = local.is_transit_gateway ? 1 : 0

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = module.eks_cluster_region_0.vpc_id
  subnet_ids         = module.eks_cluster_region_0.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-${local.owner.region_full_name}-tgw-attachment"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "region_1" {
  count    = local.is_transit_gateway ? 1 : 0
  provider = aws.accepter

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = module.eks_cluster_region_1.vpc_id
  subnet_ids         = module.eks_cluster_region_1.private_subnet_ids

  tags = {
    Name = "${var.cluster_name}-${local.accepter.region_full_name}-tgw-attachment"
  }
}

################################
# Route Table Updates          #
################################
# These are required to let the VPC know where to route the traffic to.
# In this case non local cidr range --> Transit Gateway.

resource "aws_route" "owner_tgw" {
  count = local.is_transit_gateway ? 1 : 0

  route_table_id         = module.eks_cluster_region_0.vpc_main_route_table_id
  destination_cidr_block = local.accepter.vpc_cidr_block
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "owner_private_tgw" {
  count = local.is_transit_gateway ? length(module.eks_cluster_region_0.private_route_table_ids) : 0

  route_table_id         = module.eks_cluster_region_0.private_route_table_ids[count.index]
  destination_cidr_block = local.accepter.vpc_cidr_block
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "accepter_tgw" {
  count    = local.is_transit_gateway ? 1 : 0
  provider = aws.accepter

  route_table_id         = module.eks_cluster_region_1.vpc_main_route_table_id
  destination_cidr_block = local.owner.vpc_cidr_block
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "accepter_private_tgw" {
  count    = local.is_transit_gateway ? length(module.eks_cluster_region_1.private_route_table_ids) : 0
  provider = aws.accepter

  route_table_id         = module.eks_cluster_region_1.private_route_table_ids[count.index]
  destination_cidr_block = local.owner.vpc_cidr_block
  transit_gateway_id     = var.transit_gateway_id
}

################################
# Security Groups Updates      #
################################
# These changes are required to actually allow inbound traffic from the other VPC.

resource "aws_vpc_security_group_ingress_rule" "owner_eks_primary_tgw" {
  count = local.is_transit_gateway ? 1 : 0

  security_group_id = module.eks_cluster_region_0.cluster_primary_security_group_id

  cidr_ipv4   = local.accepter.vpc_cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1
}

resource "aws_vpc_security_group_ingress_rule" "accepter_eks_primary_tgw" {
  count    = local.is_transit_gateway ? 1 : 0
  provider = aws.accepter

  security_group_id = module.eks_cluster_region_1.cluster_primary_security_group_id

  cidr_ipv4   = local.owner.vpc_cidr_block
  from_port   = -1
  ip_protocol = -1
  to_port     = -1
}
