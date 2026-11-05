prefix = "camunda-demo-b"

zone = "zone-b"
zones = [
  { name = "zone-a", number_of_brokers = 3, number_of_replicas = 3, priority = 1000 },
  { name = "zone-b", number_of_brokers = 3, number_of_replicas = 3, priority = 500 },
]

# Own name first, then region A's internal load balancer (output nlb_raft_dns_name of
# region A's exposure layer).
initial_contact_points = "orchestration-cluster-sc:26502,<nlb_raft_dns_name of region A>:26502"

enable_raft_listener               = true
cross_region_membership            = true
rdbms_async_replication_monitoring = true

# In basic authentication mode the users exist in the cluster, not in the region: use
# region A's passwords (terraform output in region A's camunda layer).
# admin_user_password      = "..."
# connectors_user_password = "..."
