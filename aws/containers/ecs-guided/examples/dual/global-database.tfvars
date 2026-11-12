prefix   = "camunda-demo"
region_a = "eu-west-1"
region_b = "eu-north-1"

# Outputs of the storage stage of region A.
source_cluster_arn         = "arn:aws:rds:eu-west-1:111111111111:cluster:camunda-demo-camunda-db-cluster"
source_cluster_identifier  = "camunda-demo-camunda-db-cluster"
source_cluster_endpoint    = "camunda-demo-camunda-db-cluster.cluster-abc.eu-west-1.rds.amazonaws.com"
source_cluster_resource_id = "cluster-ABCDEFG"

# Outputs of the network stages of both regions.
vpc_id_a             = "vpc-0aaa"
vpc_cidr_a           = "10.190.0.0/16"
vpc_id_b             = "vpc-0bbb"
vpc_cidr_b           = "10.191.0.0/16"
private_subnet_ids_b = ["subnet-b1", "subnet-b2", "subnet-b3"]
