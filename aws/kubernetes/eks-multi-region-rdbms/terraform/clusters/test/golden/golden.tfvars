# Golden plan inputs.
#
# The plan is rendered with `just regenerate-golden-file` and compared against
# tfplan-golden.json by the golden workflow. Keep this minimal: every value here
# is an input the golden plan is pinned to.
#
# `active_region_count` is deliberately the full slot count so that the golden
# plan covers every region, every Transit Gateway peering and both database
# members.
aws_profile         = null
cluster_name        = "camunda"
active_region_count = 3
