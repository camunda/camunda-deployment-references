prefix = "camunda-demo"

# Step 5: register the brokers on the internal load balancer of the exposure layer. The
# zone list stays as it is until the zone was added (see camunda-converged.tfvars).
enable_raft_listener = true
