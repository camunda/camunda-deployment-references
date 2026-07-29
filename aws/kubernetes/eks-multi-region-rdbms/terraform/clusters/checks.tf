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
