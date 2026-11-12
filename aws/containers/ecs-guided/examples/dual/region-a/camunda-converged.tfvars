# Step 10, after the zone was added through the management API: describe the whole
# cluster in region A too, so that a restart of its brokers starts from the same picture.
# Replaces camunda.tfvars of step 5 (keep enable_raft_listener = true).
prefix = "camunda-demo"

enable_raft_listener = true

zone = "zone-a"
zones = [
  { name = "zone-a", number_of_brokers = 3, number_of_replicas = 3, priority = 1000 },
  { name = "zone-b", number_of_brokers = 3, number_of_replicas = 3, priority = 500 },
]
cross_region_membership            = true
rdbms_async_replication_monitoring = true
