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

module "tgw_hub" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-hub"

  for_each = local.active_regions

  region     = each.value.region
  name       = "${var.cluster_name}-${each.value.short_name}"
  vpc_id     = local.clusters[each.key].vpc_id
  subnet_ids = local.clusters[each.key].private_subnet_ids
  vpc_route_table_ids = concat(
    [local.clusters[each.key].vpc_main_route_table_id],
    local.clusters[each.key].private_route_table_ids,
  )
  remote_cidr_blocks = local.remote_cidr_blocks[each.key]
}

locals {
  active_regions = {
    for i in local.active_indices : i => var.regions[i]
  }
}

################################################################################
# Peering mesh                                                                 #
#                                                                              #
# Pairs are ordered (i < j) so that adding a region only appends new peerings.  #
################################################################################

locals {
  tgw_peering_pairs = {
    for pair in flatten([
      for owner in local.active_indices : [
        for accepter in local.active_indices : {
          owner    = owner
          accepter = accepter
        } if owner < accepter
      ]
    ]) : "${pair.owner}_${pair.accepter}" => pair
  }
}

module "tgw_peering" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/transit-gateway-peering"

  for_each = local.tgw_peering_pairs

  name            = "${var.cluster_name}-${var.regions[each.value.owner].short_name}-${var.regions[each.value.accepter].short_name}"
  owner_region    = var.regions[each.value.owner].region
  accepter_region = var.regions[each.value.accepter].region

  owner_transit_gateway_id             = module.tgw_hub[each.value.owner].transit_gateway_id
  owner_transit_gateway_route_table_id = module.tgw_hub[each.value.owner].transit_gateway_route_table_id
  owner_cidr_blocks                    = local.region_cidr_blocks[each.value.owner]

  accepter_transit_gateway_id             = module.tgw_hub[each.value.accepter].transit_gateway_id
  accepter_transit_gateway_route_table_id = module.tgw_hub[each.value.accepter].transit_gateway_route_table_id
  accepter_cidr_blocks                    = local.region_cidr_blocks[each.value.accepter]
}
