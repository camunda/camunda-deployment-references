# AWS EC2 Reference Implementation

## Project Overview

This reference implementation can be used to deploy Camunda 8 in a highly available setup. It is split into the base infrastructure part done with Terraform and the management part using bash scripts to configure the EC2 instances and deploy Camunda 8.

This Terraform project is designed to create and manage an AWS infrastructure that includes EC2 instances and an Amazon OpenSearch Service domain. The setup includes necessary security groups, VPC, and subnet configurations to ensure secure communication between the EC2 instances and the OpenSearch domain.

## Prerequisites

Before you begin, ensure you have the following installed:

- [Terraform](https://www.terraform.io/downloads.html) (version 1.7 or later)
- [AWS CLI](https://aws.amazon.com/cli/)
- AWS account credentials configured (`aws configure`)

## Project Structure

### Configs

- `amazon-cloudwatch-agent.json`: The configuration file for the optional CloudWatch agent to export Camunda 8 logs and prometheus metrics.
- `camunda.service`: Systemd service to autostart and restart Camunda 8.
- `camunda-environment`: The base configuration for Camunda 8, which is dynamically extended to include proper node ids and ips. Can be extended by the user.
- `connectors.service`: Systemd service to autostart and restart the Connectors.
- `connectors-environment`: The configuration for Connectors, can be extended by users.
-` prometheus.yaml`: The optional prometheus scraping config required for CloudWatch.

### Scripts

- `all-in-one-install.sh`: The main script that calls up all other scripts to install all required dependencies and configures Camunda 8.
- `camunda-checks.sh`: Checks that services are running and endpoints reachable on the remote machines.
- `camunda-configure.sh`: Creates the configuration file Camunda 8 via env variables as a lot of values are dynamic.
- `camunda-install.sh`: Installs Camunda 8, Connectors, and required dependencies (Java).
- `camunda-security.sh`: (Optional) Configures secure cluster communication via TLS by using self-signed certs.
- `camunda-services.sh`: Installs Camunda 8 systemd services and copies all required config files.
- `cloudwatch-configure.sh`: (Optional) Copies configs and configures CloudWatch to export logs and Prometheus metrics.
- `cloudwatch-install.sh`: (Optional) Installs the CloudWatch agent.
- `generate-self-signed-cert-authority.sh`: (Optional) Generates a self-signed certificate authority (CA).
- `generate-self-signed-cert-node.sh`: (Optional) Generates certs based on the CA for broker/broker and gateway/client communication.

### Terraform

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

### Terraform

> [!NOTE]
> It is assumed that the user has already configured their access to AWS via the aws cli `aws configure` or by providing environment variables with access credentials.

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

### Scripts

The following scripts `camunda-install`, `camunda-checks`, `cloudwatch-install` are executed on the remote machines and environment variables have to be either set prior on the machines or the default value defined within the script as they will not take on the values of the host machine.

### Step 1: Consider optional features

There are certain features hidden behind a feature flag. Those are the following:

- `CLOUDWATCH_ENABLED`: The default is false. If set to true will install the CloudWatch agent on each EC2 instance and export Camunda logs and Prometheus metrics to AWS CloudWatch.
- `SECURITY`: The default is false. If set to true will use self-signed certificates to secure cluster communication. This requires a manual step as a prerequisite.

Additionally, environment variables can be configured to overwrite the default for Camunda and Java versions:

- `OPENJDK_VERSION`: The Temurin Java version.
- `CAMUNDA_VERSION`: The Camunda 8 version.
- `CAMUNDA_CONNECTORS_VERSION`: The Camunda 8 connectors version.

### Step 2: (Optional) Security

If you decide to enable `Security`, please execute the `generate-self-signed-cert-authority.sh` script to once create a certificate authority. It would be wise to save those somewhere securely as you'll require those if you want to upgrade or change configs in an automated way. Worst case, you'll have to recreate the certificate authority certs via the script and all manually created client certificates.

### Step 3: Execute `all-in-one-install.sh`

Run the `all-in-one-install.sh`.

It will install all required dependencies. Additionally, it configures Camunda 8 to run in a highly available setup by using a managed OpenSearch instance.

The script will pull all required IPs and other information from the Terraform state via Terraform outputs.

During the first installation, you will be asked to confirm the connection to each EC2 instance by typing `yes`.

### Step 4: Enjoy your Camunda 8 setup

Via the Terraform output `alb_endpoint` one can access Operate or on port `9090` the Connectors instance.

Via the Terraform output `nlb_endpoint` one can access the gRPC endpoint of the zeebe-gateway.

Alternatively, if you have decided not to expose your environment, you can use the jump host to access relevant services on your local machine via port-forwarding.

The following can be executed from within the Terraform folder.

```
export BASTION_HOST=$(terraform output -raw bastion_ip)
# retrieves the first IP from the camunda_ips array
export CAMUNDA_IP=$(tf output -json camunda_ips | jq -r '.[0]')

# 26500 - gRPC; 8080 - WebUI; 9090 - Connectors
ssh -L 26500:${CAMUNDA_IP}:26500 -L 8080:${CAMUNDA_IP}:8080 -L 9090:${CAMUNDA_IP}:9090 admin@${BASTION_HOST}
```
