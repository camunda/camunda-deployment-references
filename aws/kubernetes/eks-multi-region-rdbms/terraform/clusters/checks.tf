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
    condition     = var.active_region_count >= local.region_slot_count - 1
    error_message = <<-EOT
      active_region_count (${var.active_region_count}) leaves more than one region slot empty out of ${local.region_slot_count}.

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

      Merge the entries into one rule and describe both uses in its
      description.
    EOT
  }
}
