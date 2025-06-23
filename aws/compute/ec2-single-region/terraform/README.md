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
| <a name="module_opensearch_domain"></a> [opensearch\_domain](#module\_opensearch\_domain) | ../../../modules/opensearch | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | v5.21.0 |
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
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | The prefix to use for names of resources | `string` | `"camunda"` | no |
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
| <a name="output_private_key"></a> [private\_key](#output\_private\_key) | (Optional) This private key is meant for testing purposes only and enabled via the variable `generate_ssh_key_pair`. |
| <a name="output_public_key"></a> [public\_key](#output\_public\_key) | (Optional) This public key is meant for testing purposes only and enabled via the variable `generate_ssh_key_pair`. Please supply your own public key via the variable `pub_key_path`. |
<!-- END_TF_DOCS -->
