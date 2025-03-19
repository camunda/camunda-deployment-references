cluster_service_ipv4_cidr = "10.190.0.0/16"
cluster_node_ipv4_cidr    = "10.192.0.0/16"
np_instance_types         = ["t2.medium"]

# spot instances are cheaper with same performances for non production environments
np_capacity_type = "SPOT"
cluster_tags = {
  Environment = "tests"
}
np_labels = {
  Environment = "tests"
}
