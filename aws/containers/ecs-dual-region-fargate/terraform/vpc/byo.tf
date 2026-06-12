################################################################
#                  BYO-VPC Validation Checks                    #
################################################################
#
# These check blocks fail the plan at validation time if the
# BYO-VPC inputs are incomplete or if greenfield inputs leak in
# when byo_vpc = true. Per-variable validation handles shape
# (regex on vpc-xxx, subnet-xxx, rtb-xxx); these blocks handle
# the cross-variable invariants.
#
# See terraform/vpc/README.md → 'BYO-VPC requirements' for the
# full contract a customer-provided VPC must satisfy.

check "byo_vpc_required_inputs" {
  assert {
    condition = !var.byo_vpc || (
      var.region_0_vpc_id != "" &&
      var.region_0_vpc_cidr != "" &&
      length(var.region_0_private_subnet_ids) >= 3 &&
      length(var.region_0_public_subnet_ids) >= 3 &&
      length(var.region_0_private_route_table_ids) >= 1 &&
      var.region_1_vpc_id != "" &&
      var.region_1_vpc_cidr != "" &&
      length(var.region_1_private_subnet_ids) >= 3 &&
      length(var.region_1_public_subnet_ids) >= 3 &&
      length(var.region_1_private_route_table_ids) >= 1
    )
    error_message = <<-EOT
      byo_vpc = true requires all of the following per region:
        - region_N_vpc_id, region_N_vpc_cidr
        - ≥3 region_N_private_subnet_ids (across distinct AZs — used by ECS tasks AND Aurora)
        - ≥3 region_N_public_subnet_ids (across distinct AZs, with IGW route — for ALB)
        - ≥1 region_N_private_route_table_ids (for cross-region peering/TGW routes)
      See terraform/vpc/README.md → 'BYO-VPC requirements' for the full contract.
    EOT
  }
}

check "create_vpc_inputs_clean" {
  assert {
    condition = var.byo_vpc || (
      var.region_0_vpc_id == "" &&
      var.region_1_vpc_id == "" &&
      var.region_0_vpc_cidr == "" &&
      var.region_1_vpc_cidr == "" &&
      length(var.region_0_private_subnet_ids) == 0 &&
      length(var.region_1_private_subnet_ids) == 0 &&
      length(var.region_0_public_subnet_ids) == 0 &&
      length(var.region_1_public_subnet_ids) == 0 &&
      length(var.region_0_private_route_table_ids) == 0 &&
      length(var.region_1_private_route_table_ids) == 0
    )
    error_message = <<-EOT
      byo_vpc = false but one or more BYO variables (region_N_vpc_id, subnet IDs, route table IDs) are set.
      These would be silently ignored. Either clear them or set byo_vpc = true.
    EOT
  }
}
