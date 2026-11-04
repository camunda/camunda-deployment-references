# S3 Bucket Module

An encrypted, private S3 bucket with its KMS key and an IAM policy to attach to the ECS task role.

| `purpose` | Use | Versioning |
| --- | --- | --- |
| `backup` | Camunda backups. One per cluster. | on |
| `node-id-lease` | Orchestration Cluster node ID leases on ECS. **One per zone, never shared** between zones or clusters. | off |

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
