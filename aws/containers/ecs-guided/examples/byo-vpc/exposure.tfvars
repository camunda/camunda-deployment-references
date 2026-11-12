prefix = "camunda-demo"

# An internal load balancer for the traffic between brokers (26502). Nothing uses it in a
# single region, but turning it on now means growing to a second region later does not
# make Terraform replace the Orchestration Cluster ECS service, which is how the other
# region's brokers get to this one. Set it to false if you will never add a region.
enable_raft_nlb = true

# Restrict who can reach the load balancers. The default is open to the internet.
# limit_access_to_cidrs = ["203.0.113.0/24"]
