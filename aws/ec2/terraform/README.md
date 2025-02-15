# AWS EC2 Terraform Reference

<!-- TODO: Link to official docs -->

This folder contains the Terraform configuration files used to set up the AWS infrastructure for deploying Camunda 8 in a highly available setup. The configuration includes creating EC2 instances, security groups, VPC, subnets, and an Amazon OpenSearch Service domain.

## Project Structure

- `config.tf`: Contains the base configuration for the backend and required providers.
- `ec2.tf`: Contains the configuration for creating EC2 instances.
- `iam.tf`: Contains the roles required for CloudWatch.
- `opensearch.tf`: Contains the configuration for creating the OpenSearch domain.
- `alb.tf`: The configuration for the optional Application Load Balancer to expose the environment.
- `security.tf`: Security rules to define traffic within the network and from outside.
- `vpc.tf`: The required setup for the virtual private cloud, the base network for all other components.
- `variables.tf`: Defines the variables used in the Terraform scripts.
- `outputs.tf`: Specifies the outputs of the Terraform execution, such as endpoints and instance IDs.

## Setup and Usage

> [!NOTE]
> It is assumed that the user has already configured their access to AWS via the aws cli `aws configure` or by providing environment variables with access credentials.

> [!IMPORTANT]
> The `arm64` architecture is not currently supported for production environments. Please refer to the [supported environments documentation](https://docs.camunda.io/docs/reference/supported-environments/) for a list of officially supported environments.

#### Step 1: Clone the Repository

```sh
git clone https://github.com/camunda/camunda-deployment-references.git
cd camunda-deployment-references/aws/ec2/terraform
```

#### Step 2: Configure Variables

Edit the `variables.tf` file to customize the settings such as the prefix for resource names and CIDR blocks. Example:

```hcl
variable "prefix" {
  default = "example"
}

variable "cidr_blocks" {
  default = "10.0.1.0/24"
}
```

Alternatively, you can also define variables from the CLI by adding `-var "myvar=value"` to the command.

For example `terraform apply -var "prefix=camunda"`.

Be aware that you will have to manually supply those everytime you do an apply or plan, therefore consider manifesting it by editing the `variables.tf`.

#### Step 3: Initialize Terraform

Initialize the Terraform working directory. This step downloads the necessary provider plugins.

```sh
terraform init
```

#### Step 4: Define AWS region via env var

Export the AWS_REGION environment variable prior to running terraform to configure the region of the AWS provider.

```
export AWS_REGION=eu-west-1
```

#### Step 5: Deploy the Infrastructure

Apply the Terraform configuration to create the resources.

```sh
terraform apply
```

You will be prompted to confirm the changes. Type `yes` and press Enter.

#### Step 6: Access Outputs

After the infrastructure is created, you can access the outputs defined in `outputs.tf`. For example, to get the OpenSearch endpoint:

```sh
terraform output aws_opensearch_domain
```

### Step 7: Connect to remote machines via Bastion host

The Camunda VMs are not public and have to be reached via the Bastion host.
Alternatively one can utilize the [AWS VPN Client](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html) to connect securely to a private VPC. This is not covered here as the setup requires a lot more user interaction.

```
export BASTION_HOST=$(terraform output -raw bastion_ip)
# retrieves the first IP from the camunda_ips array
export CAMUNDA_IP=$(tf output -json camunda_ips | jq -r '.[0]')

ssh -J admin@${BASTION_HOST} admin@${CAMUNDA_IP}
```

#### Cleanup

To destroy all resources created by this Terraform configuration, run:

```sh
terraform destroy
```

Confirm the action by typing `yes` when prompted.

### Optional Features
There are certain features hidden behind a feature flag. Those are the following:

CLOUDWATCH_ENABLED: The default is false. If set to true will install the CloudWatch agent on each EC2 instance and export Camunda logs and Prometheus metrics to AWS CloudWatch.
SECURITY: The default is false. If set to true will use self-signed certificates to secure cluster communication. This requires a manual step as a prerequisite.

<!-- BEGIN_TF_DOCS -->
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_opensearch_domain"></a> [opensearch\_domain](#module\_opensearch\_domain) | github.com/camunda/camunda-tf-eks-module//modules/opensearch | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | v5.19.0 |
## Resources

| Name | Type |
|------|------|
| [aws_ebs_volume.camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume) | resource |
| [aws_iam_instance_profile.cloudwatch_instance_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.cloudwatch_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cloudwatch_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_instance.camunda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_key_pair.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_kms_key.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_lb.grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.grpc_26500](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_8080](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_9090](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.connectors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.connectors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_lb_target_group_attachment.grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_lb_target_group_attachment.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_security_group.allow_necessary_camunda_ports_within_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_package_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_80_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_9090](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_remote_grpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.allow_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_volume_attachment.ebs_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment) | resource |
| [tls_private_key.testing](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [aws_ami.debian](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_ami"></a> [aws\_ami](#input\_aws\_ami) | The AMI to use for the EC2 instances if empty, the latest Debian 12 AMI will be used | `string` | `""` | no |
| <a name="input_aws_instance_architecture"></a> [aws\_instance\_architecture](#input\_aws\_instance\_architecture) | The architecture of the AMI to use for the EC2 instances. Available options: x86\_64, arm64 | `string` | `"x86_64"` | no |
| <a name="input_aws_instance_type"></a> [aws\_instance\_type](#input\_aws\_instance\_type) | The instance type to use for the EC2 instances based on the architecture | `map(string)` | <pre>{<br/>  "arm64": "m7g.xlarge",<br/>  "x86_64": "m7i.xlarge"<br/>}</pre> | no |
| <a name="input_aws_instance_type_bastion"></a> [aws\_instance\_type\_bastion](#input\_aws\_instance\_type\_bastion) | The instance type to use for the bastion host based on the architecture | `map(string)` | <pre>{<br/>  "arm64": "t4g.nano",<br/>  "x86_64": "t3.nano"<br/>}</pre> | no |
| <a name="input_camunda_disk_size"></a> [camunda\_disk\_size](#input\_camunda\_disk\_size) | The size of the Camunda disk in GiB | `number` | `50` | no |
| <a name="input_cidr_blocks"></a> [cidr\_blocks](#input\_cidr\_blocks) | The CIDR block to use for the VPC | `string` | `"10.200.0.0/16"` | no |
| <a name="input_enable_alb"></a> [enable\_alb](#input\_enable\_alb) | Enable the Application Load Balancer. If false, the ALB will not be created, e.g. if a user doesn't want to publicy expose the setup. | `bool` | `true` | no |
| <a name="input_enable_jump_host"></a> [enable\_jump\_host](#input\_enable\_jump\_host) | Enable the jump host (bastion) to access the private instances | `bool` | `true` | no |
| <a name="input_enable_nlb"></a> [enable\_nlb](#input\_enable\_nlb) | Enable the Network Load Balancer. If false, the NLB will not be created. | `bool` | `true` | no |
| <a name="input_enable_opensearch"></a> [enable\_opensearch](#input\_enable\_opensearch) | Enable the OpenSearch cluster. If false, the OpenSearch cluster will not be created. Users may want to supply DBs manually themselves. | `bool` | `true` | no |
| <a name="input_enable_opensearch_logging"></a> [enable\_opensearch\_logging](#input\_enable\_opensearch\_logging) | Enable OpenSearch logging to CloudWatch Logs | `bool` | `false` | no |
| <a name="input_enable_vpc_logging"></a> [enable\_vpc\_logging](#input\_enable\_vpc\_logging) | Enable VPC flow logging to CloudWatch Logs | `bool` | `false` | no |
| <a name="input_generate_ssh_key_pair"></a> [generate\_ssh\_key\_pair](#input\_generate\_ssh\_key\_pair) | Generate an SSH key pair for the EC2 instances over the use of pub\_key\_path. Meant for testing purposes / temp environments. | `bool` | `false` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | The number of instances to create | `number` | `3` | no |
| <a name="input_limit_access_to_cidrs"></a> [limit\_access\_to\_cidrs](#input\_limit\_access\_to\_cidrs) | List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_opensearch_architecture"></a> [opensearch\_architecture](#input\_opensearch\_architecture) | The architecture of the AMI to use for the OpenSearch instances. Available options: x86\_64, arm64 | `string` | `"x86_64"` | no |
| <a name="input_opensearch_dedicated_master_type"></a> [opensearch\_dedicated\_master\_type](#input\_opensearch\_dedicated\_master\_type) | The instance type to use for the dedicated OpenSearch master nodes | `map(string)` | <pre>{<br/>  "arm64": "m7g.large.search",<br/>  "x86_64": "m7i.large.search"<br/>}</pre> | no |
| <a name="input_opensearch_disk_size"></a> [opensearch\_disk\_size](#input\_opensearch\_disk\_size) | The size of the OpenSearch disk in GiB | `number` | `50` | no |
| <a name="input_opensearch_engine_version"></a> [opensearch\_engine\_version](#input\_opensearch\_engine\_version) | The engine version of the OpenSearch cluster | `string` | `"2.15"` | no |
| <a name="input_opensearch_instance_count"></a> [opensearch\_instance\_count](#input\_opensearch\_instance\_count) | The number of instances to create | `number` | `3` | no |
| <a name="input_opensearch_instance_type"></a> [opensearch\_instance\_type](#input\_opensearch\_instance\_type) | The instance type to use for the OpenSearch instances | `map(string)` | <pre>{<br/>  "arm64": "m7g.large.search",<br/>  "x86_64": "m7i.large.search"<br/>}</pre> | no |
| <a name="input_opensearch_log_types"></a> [opensearch\_log\_types](#input\_opensearch\_log\_types) | The types of logs to publish to CloudWatch Logs | `list(string)` | <pre>[<br/>  "SEARCH_SLOW_LOGS",<br/>  "INDEX_SLOW_LOGS",<br/>  "ES_APPLICATION_LOGS"<br/>]</pre> | no |
| <a name="input_ports"></a> [ports](#input\_ports) | The ports to open for the security groups within the VPC | `map(number)` | <pre>{<br/>  "camunda_metrics_endpoint": 9600,<br/>  "camunda_web_ui": 8080,<br/>  "connectors_port": 9090,<br/>  "opensearch_https": 443,<br/>  "ssh": 22,<br/>  "zeebe_broker_network_command_api_port": 26501,<br/>  "zeebe_gateway_cluster_port": 26502,<br/>  "zeebe_gateway_network_port": 26500<br/>}</pre> | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for names of resources | `string` | `"camunda"` | no |
| <a name="input_pub_key_path"></a> [pub\_key\_path](#input\_pub\_key\_path) | The path to the public key to use for the EC2 instances for SSH access | `string` | `"~/.ssh/id_rsa.pub"` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_endpoint"></a> [alb\_endpoint](#output\_alb\_endpoint) | (Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp. |
| <a name="output_aws_ami"></a> [aws\_ami](#output\_aws\_ami) | The AMI retrieved from AWS for the latest Debian 12 image. Make sure to once pin the aws\_ami variable to avoid recreations. |
| <a name="output_aws_opensearch_domain"></a> [aws\_opensearch\_domain](#output\_aws\_opensearch\_domain) | (Optional) The endpoint of the OpenSearch domain. |
| <a name="output_aws_opensearch_domain_name"></a> [aws\_opensearch\_domain\_name](#output\_aws\_opensearch\_domain\_name) | The name of the OpenSearch domain. |
| <a name="output_bastion_ip"></a> [bastion\_ip](#output\_bastion\_ip) | (Optional) The public IP address of the Bastion instance. |
| <a name="output_camunda_ips"></a> [camunda\_ips](#output\_camunda\_ips) | The private IP addresses of the Camunda instances. |
| <a name="output_nlb_endpoint"></a> [nlb\_endpoint](#output\_nlb\_endpoint) | (Optional) The DNS name of the Network Load Balancer (NLB) to access the Camunda REST API. |
| <a name="output_ports"></a> [ports](#output\_ports) | The ports to open in the security group within the VPC. For easier consumption in scripts. |
| <a name="output_private_key"></a> [private\_key](#output\_private\_key) | (Optional) This private key is meant for testing purposes only and enabled via the variable `generate_ssh_key_pair`. |
| <a name="output_public_key"></a> [public\_key](#output\_public\_key) | (Optional) This public key is meant for testing purposes only and enabled via the variable `generate_ssh_key_pair`. Please supply your own public key via the variable `pub_key_path`. |
<!-- END_TF_DOCS -->
