prefix = "camunda-demo"

# The brokers of region B join through this internal load balancer. Enable it from the
# start if you expect to grow: adding it later makes the camunda layer register a target
# group on an existing ECS service, which Terraform may replace.
enable_raft_nlb = true
