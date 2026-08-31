################################################################################
# Topology guardrails                                                          #
#                                                                              #
# Terraform variable validation cannot reference another variable, so the       #
# cross-variable invariants of the region topology are asserted here. `check`   #
# blocks report during plan without blocking a destroy, which keeps the         #
# reference architecture recoverable when a region is intentionally torn down.  #
################################################################################

check "active_region_count_within_slots" {
  assert {
    condition     = var.active_region_count <= local.region_slot_count
    error_message = "active_region_count (${var.active_region_count}) exceeds the number of region slots (${local.region_slot_count}). Add a slot to var.regions first."
  }
}

check "quorum_preserved_during_growth" {
  assert {
    condition     = 2 * var.active_region_count > local.region_slot_count
    error_message = <<-EOT
      active_region_count (${var.active_region_count}) is not a majority of the ${local.region_slot_count} region slots.

      With replicationFactor == number of region slots, each Zeebe partition
      places exactly one replica per slot. Leaving two or more slots empty
      means every partition loses its majority and the cluster cannot form a
      quorum. Bootstrap with at least ${local.region_slot_count - 1} regions,
      then activate the remaining one.
    EOT
  }
}

check "cross_region_rules_are_unique" {
  assert {
    condition = length(local.cross_region_rules) == length(distinct([
      for rule in local.cross_region_rules :
      "${rule.ip_protocol}|${rule.from_port}|${rule.to_port}"
    ]))
    error_message = <<-EOT
      Two entries in local.cross_region_rules share the same protocol and port
      range.

      Terraform keys these rules by name, so duplicates look like distinct
      resources, but AWS deduplicates security group rules by protocol, port
      range and source. The second one is rejected at apply time with
      InvalidPermission.Duplicate, after the clusters and the database have
      already been created.

      Merge the entries into one rule, widening the port range if needed, and
      describe both uses in its description.
    EOT
  }
}

check "cross_region_rules_fit_the_security_group_quota" {
  assert {
    condition     = max(0, var.active_region_count - 1) * 2 * length(local.cross_region_rules) <= 60
    error_message = <<-EOT
      The cross-region ingress rules exceed the AWS limit of 60 inbound rules
      per security group.

      Every rule is instantiated once per remote CIDR, and each remote region
      contributes two (its VPC range and its service range), so the count grows
      linearly with active_region_count. Exceeding it fails at apply time,
      after the clusters have been built. Merge port ranges rather than raising
      the quota.
    EOT
  }
}
