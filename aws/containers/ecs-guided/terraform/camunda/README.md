# Camunda stage

The Orchestration Cluster (zone-aware brokers, S3 node ID lease) and Connectors. It creates no network, storage, load balancer or identity: they arrive as variables from the other stages.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_connectors"></a> [connectors](#module\_connectors) | ../../../../modules/ecs/fargate/connectors | n/a |
| <a name="module_orchestration_cluster"></a> [orchestration\_cluster](#module\_orchestration\_cluster) | ../../../../modules/ecs/fargate/orchestration-cluster | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.basic_auth_secrets_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role_policy_attachment.basic_auth_secrets_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_secretsmanager_secret.admin_user_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.connectors_user_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.admin_user_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.connectors_user_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [random_password.admin_user](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.connectors_user](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [terraform_data.database_ready](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.validate](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_user_password"></a> [admin\_user\_password](#input\_admin\_user\_password) | Password of the admin user in basic authentication mode. Empty generates one. A second region must receive the first region's: the user exists in the cluster, not in each region. | `string` | `""` | no |
| <a name="input_alb_listener_http_management_arn"></a> [alb\_listener\_http\_management\_arn](#input\_alb\_listener\_http\_management\_arn) | Exposure stage output: listener for the management endpoint | `string` | n/a | yes |
| <a name="input_alb_listener_http_webapp_arn"></a> [alb\_listener\_http\_webapp\_arn](#input\_alb\_listener\_http\_webapp\_arn) | Exposure stage output: listener the web app rules attach to | `string` | n/a | yes |
| <a name="input_backup_access_policy_arn"></a> [backup\_access\_policy\_arn](#input\_backup\_access\_policy\_arn) | Object storage stage output: policy granting access to the backup bucket | `string` | n/a | yes |
| <a name="input_backup_bucket_name"></a> [backup\_bucket\_name](#input\_backup\_bucket\_name) | Object storage stage output: backup bucket | `string` | n/a | yes |
| <a name="input_camunda_ports_security_group_id"></a> [camunda\_ports\_security\_group\_id](#input\_camunda\_ports\_security\_group\_id) | Compute stage output: security group that opens the Camunda ports inside the VPC | `string` | n/a | yes |
| <a name="input_camunda_version"></a> [camunda\_version](#input\_camunda\_version) | Version that Camunda Hub is told this cluster runs. From 8.8 on it selects the REST and gRPC cluster API. Keep it in sync with the image of the Orchestration Cluster. | `string` | `"8.10.0"` | no |
| <a name="input_connectors_user_password"></a> [connectors\_user\_password](#input\_connectors\_user\_password) | Password of the connectors user in basic authentication mode. Empty generates one. A second region must receive the first region's: the user exists in the cluster, not in each region. | `string` | `""` | no |
| <a name="input_cross_region_membership"></a> [cross\_region\_membership](#input\_cross\_region\_membership) | Relax the membership probe and failure timeouts for the latency between regions (the defaults are too tight for a cross-region link). | `bool` | `false` | no |
| <a name="input_db_seed_done"></a> [db\_seed\_done](#input\_db\_seed\_done) | Storage stage output: changes once the database users exist. Only used to order the deployment. | `string` | `""` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags applied to every resource created by this root | `map(string)` | `{}` | no |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | Compute stage output: ID of the ECS cluster | `string` | n/a | yes |
| <a name="input_efs_security_group_id"></a> [efs\_security\_group\_id](#input\_efs\_security\_group\_id) | Compute stage output: security group of the EFS file systems | `string` | n/a | yes |
| <a name="input_egress_security_group_id"></a> [egress\_security\_group\_id](#input\_egress\_security\_group\_id) | Compute stage output: security group that allows outbound HTTP and HTTPS | `string` | n/a | yes |
| <a name="input_enable_management_endpoint"></a> [enable\_management\_endpoint](#input\_enable\_management\_endpoint) | Publish the management endpoint (9600) on the load balancer. It is unauthenticated: leave it off and reach it through a jump host or a VPN. | `bool` | `false` | no |
| <a name="input_enable_raft_listener"></a> [enable\_raft\_listener](#input\_enable\_raft\_listener) | Register the brokers on raft\_nlb\_arn (port 26502). A plain flag, not derived from the ARN, because Terraform must know it at plan time. | `bool` | `false` | no |
| <a name="input_initial_contact_points"></a> [initial\_contact\_points](#input\_initial\_contact\_points) | Initial contact points of the cluster (host:26502, comma separated). Empty keeps the local Service Connect name. A second region lists its own name and the first region's raft\_nlb\_dns\_name here. | `string` | `""` | no |
| <a name="input_lease_bucket"></a> [lease\_bucket](#input\_lease\_bucket) | Object storage stage output lease\_buckets[<zone>]: the node ID lease bucket of this zone. One bucket per zone, never shared. | <pre>object({<br/>    bucket_name       = string<br/>    access_policy_arn = string<br/>  })</pre> | n/a | yes |
| <a name="input_nlb_grpc_arn"></a> [nlb\_grpc\_arn](#input\_nlb\_grpc\_arn) | Exposure stage output: network load balancer for gRPC | `string` | n/a | yes |
| <a name="input_oidc"></a> [oidc](#input\_oidc) | Identity stage output oidc. null selects basic authentication with built-in users. | <pre>object({<br/>    issuer_uri      = string<br/>    token_uri       = string<br/>    audience        = string<br/>    redirect_uri    = string<br/>    username_claim  = string<br/>    client_id_claim = string<br/>    admin_claim     = string<br/>    orchestration = object({<br/>      client_id         = string<br/>      client_secret_arn = string<br/>    })<br/>    connectors = object({<br/>      client_id         = string<br/>      client_secret_arn = string<br/>      token_scope       = string<br/>    })<br/>  })</pre> | `null` | no |
| <a name="input_partition_count"></a> [partition\_count](#input\_partition\_count) | Number of partitions. It does not change when a zone is added. | `number` | `3` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | Name prefix of the services and secrets | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Network stage output: private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_raft_nlb_arn"></a> [raft\_nlb\_arn](#input\_raft\_nlb\_arn) | Exposure stage output nlb\_raft\_arn: internal load balancer on which the brokers of other regions reach this one. Required when enable\_raft\_listener = true. | `string` | `""` | no |
| <a name="input_rdbms_async_replication_monitoring"></a> [rdbms\_async\_replication\_monitoring](#input\_rdbms\_async\_replication\_monitoring) | Hold the Zeebe log until the secondary storage confirms replication to its replica region. Turn it on when the database is an Aurora Global Database. | `bool` | `false` | no |
| <a name="input_rds_db_connect_policy_arn"></a> [rds\_db\_connect\_policy\_arn](#input\_rds\_db\_connect\_policy\_arn) | Storage stage output rds\_db\_connect\_policy\_arns["camunda"]: lets the task role connect as the camunda database user | `string` | n/a | yes |
| <a name="input_registry_credentials_arn"></a> [registry\_credentials\_arn](#input\_registry\_credentials\_arn) | Compute stage output: registry credentials secret, empty for public images | `string` | `""` | no |
| <a name="input_secondary_storage"></a> [secondary\_storage](#input\_secondary\_storage) | Storage stage output: connection settings of the secondary storage | <pre>object({<br/>    type                   = string<br/>    host                   = string<br/>    port                   = number<br/>    database_name          = string<br/>    jdbc_url               = string<br/>    jdbc_driver_class_name = string<br/>    iam_auth_enabled       = bool<br/>  })</pre> | n/a | yes |
| <a name="input_secrets_kms_key_arn"></a> [secrets\_kms\_key\_arn](#input\_secrets\_kms\_key\_arn) | Compute stage output: KMS key that encrypts the secrets | `string` | n/a | yes |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | Compute stage output: ARN of the task execution role | `string` | n/a | yes |
| <a name="input_task_execution_role_name"></a> [task\_execution\_role\_name](#input\_task\_execution\_role\_name) | Compute stage output: name of the task execution role, to attach the secret read policy of this stage | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Network stage output: ID of the VPC | `string` | n/a | yes |
| <a name="input_zone"></a> [zone](#input\_zone) | Zone of this deployment. The brokers are named <zone>\_<index>. Growing to a second region later adds a zone: it does not rename these brokers. | `string` | `"zone-a"` | no |
| <a name="input_zones"></a> [zones](#input\_zones) | Every zone of the cluster. List only zones whose brokers run. The replication factor is the sum of number\_of\_replicas. | <pre>list(object({<br/>    name               = string<br/>    number_of_brokers  = number<br/>    number_of_replicas = number<br/>    priority           = number<br/>  }))</pre> | <pre>[<br/>  {<br/>    "name": "zone-a",<br/>    "number_of_brokers": 3,<br/>    "number_of_replicas": 3,<br/>    "priority": 1000<br/>  }<br/>]</pre> | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_admin_user_password"></a> [admin\_user\_password](#output\_admin\_user\_password) | Password of the admin user in basic authentication mode, empty with OIDC. Also stored in Secrets Manager. |
| <a name="output_cluster_registration"></a> [cluster\_registration](#output\_cluster\_registration) | What Camunda Hub needs to connect to this cluster: add it to the clusters of the Camunda Hub stage. The addresses are service discovery names that resolve inside the VPC, and in a peered VPC through the Route 53 Resolver rules of the interconnect. |
| <a name="output_connectors_user_password"></a> [connectors\_user\_password](#output\_connectors\_user\_password) | Password of the connectors user in basic authentication mode, empty with OIDC. A second region takes it as connectors\_user\_password. |
| <a name="output_grpc_service_connect"></a> [grpc\_service\_connect](#output\_grpc\_service\_connect) | Service Connect name of the gRPC endpoint, reachable inside the ECS cluster |
| <a name="output_lease_bucket_name"></a> [lease\_bucket\_name](#output\_lease\_bucket\_name) | Node ID lease bucket used by this zone |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | CloudWatch log group of the Orchestration Cluster |
| <a name="output_rest_service_connect"></a> [rest\_service\_connect](#output\_rest\_service\_connect) | Service Connect name of the REST endpoint, reachable inside the ECS cluster |
<!-- END_TF_DOCS -->
