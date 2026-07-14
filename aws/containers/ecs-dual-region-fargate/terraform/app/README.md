# app

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_connectors_region_0"></a> [connectors\_region\_0](#module\_connectors\_region\_0) | ../../../../modules/ecs/fargate/connectors | n/a |
| <a name="module_connectors_region_1"></a> [connectors\_region\_1](#module\_connectors\_region\_1) | ../../../../modules/ecs/fargate/connectors | n/a |
| <a name="module_orchestration_cluster_region_0"></a> [orchestration\_cluster\_region\_0](#module\_orchestration\_cluster\_region\_0) | ../../../../modules/ecs/fargate/orchestration-cluster | n/a |
| <a name="module_orchestration_cluster_region_1"></a> [orchestration\_cluster\_region\_1](#module\_orchestration\_cluster\_region\_1) | ../../../../modules/ecs/fargate/orchestration-cluster | n/a |
## Resources

| Name | Type |
| ---- | ---- |
| [aws_region.region_0](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_region.region_1](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [terraform_remote_state.infra](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | AWS Profile to use (null = use default credential chain) | `string` | `null` | no |
| <a name="input_camunda_image"></a> [camunda\_image](#input\_camunda\_image) | Container image for the Camunda orchestration cluster tasks (Zeebe broker + gateway + webapps) | `string` | `"camunda/camunda:8.10-SNAPSHOT"` | no |
| <a name="input_connectors_image"></a> [connectors\_image](#input\_connectors\_image) | Container image for the Camunda connectors-bundle tasks. Separate from camunda\_image because connectors ship as a distinct artifact from the orchestration cluster. | `string` | `"camunda/connectors-bundle:8.10-SNAPSHOT"` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_region_0"></a> [region\_0](#input\_region\_0) | AWS region for the primary (owner) cluster (must match infra/ and vpc/ configuration) | `string` | `"eu-west-2"` | no |
| <a name="input_region_1"></a> [region\_1](#input\_region\_1) | AWS region for the secondary (accepter) cluster (must match infra/ and vpc/ configuration) | `string` | `"eu-west-3"` | no |
| <a name="input_terraform_backend_bucket"></a> [terraform\_backend\_bucket](#input\_terraform\_backend\_bucket) | S3 bucket name storing Terraform state for all layers | `string` | n/a | yes |
| <a name="input_terraform_backend_key_prefix"></a> [terraform\_backend\_key\_prefix](#input\_terraform\_backend\_key\_prefix) | S3 key prefix shared by all layers. E.g. 'aws/containers/ecs-dual-region-fargate/my-cluster/' yields 's3://<bucket>/<prefix>infra/terraform.tfstate' | `string` | n/a | yes |
| <a name="input_terraform_backend_region"></a> [terraform\_backend\_region](#input\_terraform\_backend\_region) | AWS region of the S3 bucket storing Terraform state (may differ from the deployment regions) | `string` | `"eu-central-1"` | no |
## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_admin_user_password"></a> [admin\_user\_password](#output\_admin\_user\_password) | The admin password for Camunda |
| <a name="output_next_steps"></a> [next\_steps](#output\_next\_steps) | Operator handover: how to fetch credentials and access the deployment. |
| <a name="output_region_0_alb_endpoint"></a> [region\_0\_alb\_endpoint](#output\_region\_0\_alb\_endpoint) | The DNS name of the ALB in region 0 (HTTP/REST access) |
| <a name="output_region_0_log_group_name"></a> [region\_0\_log\_group\_name](#output\_region\_0\_log\_group\_name) | CloudWatch log group for the orchestration cluster in region 0 |
| <a name="output_region_0_nlb_grpc_endpoint"></a> [region\_0\_nlb\_grpc\_endpoint](#output\_region\_0\_nlb\_grpc\_endpoint) | The DNS name of the external NLB in region 0 (gRPC access) |
| <a name="output_region_1_alb_endpoint"></a> [region\_1\_alb\_endpoint](#output\_region\_1\_alb\_endpoint) | The DNS name of the ALB in region 1 (HTTP/REST access) |
| <a name="output_region_1_log_group_name"></a> [region\_1\_log\_group\_name](#output\_region\_1\_log\_group\_name) | CloudWatch log group for the orchestration cluster in region 1 |
| <a name="output_region_1_nlb_grpc_endpoint"></a> [region\_1\_nlb\_grpc\_endpoint](#output\_region\_1\_nlb\_grpc\_endpoint) | The DNS name of the external NLB in region 1 (gRPC access) |
<!-- END_TF_DOCS -->
