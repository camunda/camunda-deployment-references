# RDS Aurora Module

Terraform module which creates Aurora RDS resources with an opinionated configuration targeting Camunda 8.

## Usage

Following is a simple example configuration and should be adjusted as required.

See [inputs](#inputs) for further configuration options and how they affect the RDS creation.

```hcl
module "postgresql" {
  source                     = "github.com/camunda/camunda-tf-eks-module/modules/aurora"
  engine_version             = "15.4"
  auto_minor_version_upgrade = false
  cluster_name               = "cluster-name-postgresql"

  username         = "username"
  password         = "password"
  vpc_id           = module.eks_cluster.vpc_id
  subnet_ids       = module.eks_cluster.private_subnet_ids
  cidr_blocks      = concat(module.eks_cluster.private_vpc_cidr_blocks, module.eks_cluster.public_vpc_cidr_blocks)
  instance_class   = "db.t3.medium"
  iam_auth_enabled = true

  depends_on = [module.eks_cluster]
}
```

<!-- BEGIN_TF_DOCS -->
## Modules

No modules.
## Resources

| Name | Type |
|------|------|
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_policy.access_policies](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.roles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.attach_policies](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_rds_cluster.aurora_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.aurora_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.allow_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.allow_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | If true, minor engine upgrades will be applied automatically to the DB instance during the maintenance window | `bool` | `true` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Array of availability zones to use for the Aurora cluster | `list(string)` | <pre>[<br/>  "eu-central-1a",<br/>  "eu-central-1b",<br/>  "eu-central-1c"<br/>]</pre> | no |
| <a name="input_ca_cert_identifier"></a> [ca\_cert\_identifier](#input\_ca\_cert\_identifier) | Specifies the identifier of the CA certificate for the DB instance | `string` | `"rds-ca-rsa2048-g1"` | no |
| <a name="input_cidr_blocks"></a> [cidr\_blocks](#input\_cidr\_blocks) | The CIDR blocks to allow acces from and to. | `list(string)` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster, also used to prefix dependent resources. Format: /[[:lower:][:digit:]-]/ | `any` | n/a | yes |
| <a name="input_default_database_name"></a> [default\_database\_name](#input\_default\_database\_name) | The name for the automatically created database on cluster creation. | `string` | `"camunda"` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | The engine type e.g. aurora, aurora-mysql, aurora-postgresql, ... | `string` | `"aurora-postgresql"` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | The DB engine version for Postgres to use. | `string` | `"15.4"` | no |
| <a name="input_iam_auth_enabled"></a> [iam\_auth\_enabled](#input\_iam\_auth\_enabled) | Determines whether IAM auth should be activated for IRSA usage | `bool` | `false` | no |
| <a name="input_iam_roles"></a> [iam\_roles](#input\_iam\_roles) | Allows propagating additional IAM roles to the Aurora cluster to allow e.g. access to S3 | `list(string)` | `[]` | no |
| <a name="input_iam_roles_with_policies"></a> [iam\_roles\_with\_policies](#input\_iam\_roles\_with\_policies) | List of roles with their trust and access policies | <pre>list(object({<br/>    # Name of the Role to create<br/>    role_name = string<br/><br/>    # Assume role trust policy for this Aurora role as a json string<br/>    trust_policy = string<br/><br/>    # Access policy for Aurora allowing access as a json string<br/>    # see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html<br/>    # Since the DbiResourceId may be unknown during the apply process, and because each instance of the RDS cluster contains its own DbiResourceId,<br/>    # we use the wildcard `dbuser:*` to apply to all database instances.<br/>    # Example:<br/>    #   [<br/>    #     {<br/>    #     role_name      = "AuroraRole"<br/>    #     trust_policy   =<br/>    #           {<br/>    #             "Version": "2012-10-17",<br/>    #             "Statement": [<br/>    #               {<br/>    #                 "Effect": "Allow",<br/>    #                 "Principal": {<br/>    #                   "Federated": "arn:aws:iam::<YOUR-ACCOUNT-ID>:oidc-provider/oidc.eks.<YOUR-REGION>.amazonaws.com/id/<YOUR-OIDC-ID>"<br/>    #                 },<br/>    #                 "Action": "sts:AssumeRoleWithWebIdentity",<br/>    #                 "Condition": {<br/>    #                   "StringEquals": {<br/>    #                     "oidc.eks.<YOUR-REGION>.amazonaws.com/id/<YOUR-OIDC-PROVIDER-ID>:sub": "system:serviceaccount:<YOUR-NAMESPACE>:<YOUR-SA-NAME>"<br/>    #                   }<br/>    #                 }<br/>    #               }<br/>    #             ]<br/>    #           }<br/>    #<br/>    #     access_policy  =<br/>    #             {<br/>    #               "Version": "2012-10-17",<br/>    #               "Statement": [<br/>    #                 {<br/>    #                   "Effect": "Allow",<br/>    #                   "Action": [<br/>    #                     "rds-db:connect"<br/>    #                   ],<br/>    #                   "Resource": "arn:aws:rds-db:<YOUR-REGION>:<YOUR-ACCOUNT-ID>:dbuser:*/<YOUR-DB-USER-NAME>"<br/>    #                 }<br/>    #               ]<br/>    #             }<br/>    #<br/>    #   }<br/>    #   ]<br/>    access_policy = string<br/>  }))</pre> | `[]` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | The instance type of the Aurora instances | `string` | `"db.t3.medium"` | no |
| <a name="input_num_instances"></a> [num\_instances](#input\_num\_instances) | Number of instances | `string` | `"1"` | no |
| <a name="input_password"></a> [password](#input\_password) | The password for the postgres admin user. Important: secret value! | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | The subnet IDs to create the cluster in. For easier usage we are passing through the subnet IDs from the AWS EKS Cluster module. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to add to the resources | `map` | `{}` | no |
| <a name="input_username"></a> [username](#input\_username) | The username for the postgres admin user. Important: secret value! | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC ID to create the cluster in. For easier usage we are passing through the VPC ID from the AWS EKS Cluster module. | `any` | n/a | yes |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aurora_cluster_identifier"></a> [aurora\_cluster\_identifier](#output\_aurora\_cluster\_identifier) | RDS Cluster Identifier |
| <a name="output_aurora_cluster_resource_id"></a> [aurora\_cluster\_resource\_id](#output\_aurora\_cluster\_resource\_id) | RDS Cluster Resource ID |
| <a name="output_aurora_endpoint"></a> [aurora\_endpoint](#output\_aurora\_endpoint) | The endpoint of the Aurora cluster |
| <a name="output_aurora_iam_role_access_policy_arns"></a> [aurora\_iam\_role\_access\_policy\_arns](#output\_aurora\_iam\_role\_access\_policy\_arns) | Map of IAM role names to their access policy ARNs |
| <a name="output_aurora_iam_role_arns"></a> [aurora\_iam\_role\_arns](#output\_aurora\_iam\_role\_arns) | Map of IAM role names to their ARNs |
| <a name="output_aurora_id"></a> [aurora\_id](#output\_aurora\_id) | RDS Cluster Identifier |
<!-- END_TF_DOCS -->
