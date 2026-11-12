prefix = "camunda-demo"

additional_cidr_blocks = ["10.191.0.0/16"]

# Global Databases do not support db.t3 / db.t4g: resize first (step 1 of the runbook).
db_instance_class = "db.r6g.large"

# Step 6: once the global-database root has run, set its output global_cluster_identifier
# here so that Terraform does not plan to detach the cluster.
# global_cluster_identifier = "camunda-demo-global-db"
