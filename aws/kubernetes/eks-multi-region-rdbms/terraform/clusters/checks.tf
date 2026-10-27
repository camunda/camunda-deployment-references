################################################################################
# Topology guardrails                                                          #
#                                                                              #
# Terraform variable validation cannot reference another variable, and it also  #
# runs on destroy: an invalid value would lock the state in place, which is the #
# opposite of what a reference architecture needs when a topology has to be     #
# torn down. `check` blocks avoid that, but they only warn about invalid         #
# topology, such as an active count that exceeds the available region slots.    #
# Variable validation also rejects overlapping VPC and service CIDRs.           #
#                                                                              #
# A precondition on a resource is evaluated when that resource is created or    #
# updated and skipped when it is destroyed, which is exactly the asymmetry      #
# wanted here: an invalid topology fails the apply, a teardown still runs.      #
################################################################################

resource "terraform_data" "topology_guard" {
  input = "${var.active_region_count}/${local.region_slot_count}"

  lifecycle {
    precondition {
      condition     = var.active_region_count <= local.region_slot_count
      error_message = "active_region_count (${var.active_region_count}) exceeds the number of region slots (${local.region_slot_count}). Add a slot to var.regions first."
    }

    precondition {
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

    precondition {
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
}
