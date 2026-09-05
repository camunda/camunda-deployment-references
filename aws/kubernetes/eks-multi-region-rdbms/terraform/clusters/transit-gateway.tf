################################################################################
# Cross-region L3 connectivity: Transit Gateway full mesh                      #
#                                                                              #
# Transit Gateway peering is point-to-point and NOT transitive: traffic cannot  #
# hop through an intermediate Transit Gateway. An N-region topology therefore   #
# needs N hubs and N*(N-1)/2 peerings.                                          #
#                                                                              #
# Transit Gateway is used instead of the VPC peering mesh of the dual-region    #
# reference architecture because it keeps a single attachment per VPC as        #
# regions are added, and because the same hub can later carry on-premises or    #
# Direct Connect attachments.                                                   #
################################################################################

module "tgw_hub_region_0" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-hub"

  count = var.active_region_count > 0 ? 1 : 0

  name       = "${var.cluster_name}-${var.regions[0].short_name}"
  vpc_id     = local.clusters[0].vpc_id
  subnet_ids = local.clusters[0].private_subnet_ids
  vpc_route_table_ids = concat(
    [local.clusters[0].vpc_main_route_table_id],
    local.clusters[0].private_route_table_ids,
  )
  remote_cidr_blocks = local.remote_cidr_blocks[0]
}

module "tgw_hub_region_1" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-hub"

  count = var.active_region_count > 1 ? 1 : 0

  name       = "${var.cluster_name}-${var.regions[1].short_name}"
  vpc_id     = local.clusters[1].vpc_id
  subnet_ids = local.clusters[1].private_subnet_ids
  vpc_route_table_ids = concat(
    [local.clusters[1].vpc_main_route_table_id],
    local.clusters[1].private_route_table_ids,
  )
  remote_cidr_blocks = local.remote_cidr_blocks[1]

  providers = {
    aws = aws.region_1
  }
}

module "tgw_hub_region_2" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-hub"

  count = var.active_region_count > 2 ? 1 : 0

  name       = "${var.cluster_name}-${var.regions[2].short_name}"
  vpc_id     = local.clusters[2].vpc_id
  subnet_ids = local.clusters[2].private_subnet_ids
  vpc_route_table_ids = concat(
    [local.clusters[2].vpc_main_route_table_id],
    local.clusters[2].private_route_table_ids,
  )
  remote_cidr_blocks = local.remote_cidr_blocks[2]

  providers = {
    aws = aws.region_2
  }
}

module "tgw_hub_region_3" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-hub"

  count = var.active_region_count > 3 ? 1 : 0

  name       = "${var.cluster_name}-${var.regions[3].short_name}"
  vpc_id     = local.clusters[3].vpc_id
  subnet_ids = local.clusters[3].private_subnet_ids
  vpc_route_table_ids = concat(
    [local.clusters[3].vpc_main_route_table_id],
    local.clusters[3].private_route_table_ids,
  )
  remote_cidr_blocks = local.remote_cidr_blocks[3]

  providers = {
    aws = aws.region_3
  }
}

locals {
  tgw_hubs = {
    for i, m in [
      module.tgw_hub_region_0,
      module.tgw_hub_region_1,
      module.tgw_hub_region_2,
      module.tgw_hub_region_3,
    ] : i => one(m) if length(m) > 0
  }
}

################################################################################
# Peering mesh                                                                 #
#                                                                              #
# Pairs are ordered (i < j) so that adding a region only appends new peerings.  #
################################################################################

module "tgw_peering_0_1" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-peering"

  count = var.active_region_count > 1 ? 1 : 0

  name = "${var.cluster_name}-${var.regions[0].short_name}-${var.regions[1].short_name}"

  owner_transit_gateway_id             = local.tgw_hubs[0].transit_gateway_id
  owner_transit_gateway_route_table_id = local.tgw_hubs[0].transit_gateway_route_table_id
  owner_cidr_blocks                    = local.region_cidr_blocks[0]

  accepter_transit_gateway_id             = local.tgw_hubs[1].transit_gateway_id
  accepter_transit_gateway_route_table_id = local.tgw_hubs[1].transit_gateway_route_table_id
  accepter_cidr_blocks                    = local.region_cidr_blocks[1]

  providers = {
    aws.owner    = aws
    aws.accepter = aws.region_1
  }
}

module "tgw_peering_0_2" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-peering"

  count = var.active_region_count > 2 ? 1 : 0

  name = "${var.cluster_name}-${var.regions[0].short_name}-${var.regions[2].short_name}"

  owner_transit_gateway_id             = local.tgw_hubs[0].transit_gateway_id
  owner_transit_gateway_route_table_id = local.tgw_hubs[0].transit_gateway_route_table_id
  owner_cidr_blocks                    = local.region_cidr_blocks[0]

  accepter_transit_gateway_id             = local.tgw_hubs[2].transit_gateway_id
  accepter_transit_gateway_route_table_id = local.tgw_hubs[2].transit_gateway_route_table_id
  accepter_cidr_blocks                    = local.region_cidr_blocks[2]

  providers = {
    aws.owner    = aws
    aws.accepter = aws.region_2
  }
}

module "tgw_peering_1_2" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-peering"

  count = var.active_region_count > 2 ? 1 : 0

  name = "${var.cluster_name}-${var.regions[1].short_name}-${var.regions[2].short_name}"

  owner_transit_gateway_id             = local.tgw_hubs[1].transit_gateway_id
  owner_transit_gateway_route_table_id = local.tgw_hubs[1].transit_gateway_route_table_id
  owner_cidr_blocks                    = local.region_cidr_blocks[1]

  accepter_transit_gateway_id             = local.tgw_hubs[2].transit_gateway_id
  accepter_transit_gateway_route_table_id = local.tgw_hubs[2].transit_gateway_route_table_id
  accepter_cidr_blocks                    = local.region_cidr_blocks[2]

  providers = {
    aws.owner    = aws.region_1
    aws.accepter = aws.region_2
  }
}

module "tgw_peering_0_3" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-peering"

  count = var.active_region_count > 3 ? 1 : 0

  name = "${var.cluster_name}-${var.regions[0].short_name}-${var.regions[3].short_name}"

  owner_transit_gateway_id             = local.tgw_hubs[0].transit_gateway_id
  owner_transit_gateway_route_table_id = local.tgw_hubs[0].transit_gateway_route_table_id
  owner_cidr_blocks                    = local.region_cidr_blocks[0]

  accepter_transit_gateway_id             = local.tgw_hubs[3].transit_gateway_id
  accepter_transit_gateway_route_table_id = local.tgw_hubs[3].transit_gateway_route_table_id
  accepter_cidr_blocks                    = local.region_cidr_blocks[3]

  providers = {
    aws.owner    = aws
    aws.accepter = aws.region_3
  }
}

module "tgw_peering_1_3" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-peering"

  count = var.active_region_count > 3 ? 1 : 0

  name = "${var.cluster_name}-${var.regions[1].short_name}-${var.regions[3].short_name}"

  owner_transit_gateway_id             = local.tgw_hubs[1].transit_gateway_id
  owner_transit_gateway_route_table_id = local.tgw_hubs[1].transit_gateway_route_table_id
  owner_cidr_blocks                    = local.region_cidr_blocks[1]

  accepter_transit_gateway_id             = local.tgw_hubs[3].transit_gateway_id
  accepter_transit_gateway_route_table_id = local.tgw_hubs[3].transit_gateway_route_table_id
  accepter_cidr_blocks                    = local.region_cidr_blocks[3]

  providers = {
    aws.owner    = aws.region_1
    aws.accepter = aws.region_3
  }
}

module "tgw_peering_2_3" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-peering"

  count = var.active_region_count > 3 ? 1 : 0

  name = "${var.cluster_name}-${var.regions[2].short_name}-${var.regions[3].short_name}"

  owner_transit_gateway_id             = local.tgw_hubs[2].transit_gateway_id
  owner_transit_gateway_route_table_id = local.tgw_hubs[2].transit_gateway_route_table_id
  owner_cidr_blocks                    = local.region_cidr_blocks[2]

  accepter_transit_gateway_id             = local.tgw_hubs[3].transit_gateway_id
  accepter_transit_gateway_route_table_id = local.tgw_hubs[3].transit_gateway_route_table_id
  accepter_cidr_blocks                    = local.region_cidr_blocks[3]

  providers = {
    aws.owner    = aws.region_2
    aws.accepter = aws.region_3
  }
}
