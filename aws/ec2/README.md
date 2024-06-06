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

### Scripts

### Terraform

- `config.tf`: Contains the base configuration for the backend and required providers.
- `ec2.tf`: Contains the configuration for creating EC2 instances.
- `opensearch.tf`: Contains the configuration for creating the OpenSearch domain.
- `alb.tf`: The configuration for the optional Application Load Balancer to expose the environment.
- `security.tf`: Security rules to define traffic within the network and from outside.
- `vpc.tf`: The required setup for the virtual private cloud, the base network for all other components.
- `variables.tf`: Defines the variables used in the Terraform scripts.
- `outputs.tf`: Specifies the outputs of the Terraform execution, such as endpoints and instance IDs.

## Setup and Usage

### Terraform

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

#### Step 3: Initialize Terraform

Initialize the Terraform working directory. This step downloads the necessary provider plugins.

```sh
terraform init
```

#### Step 4: Deploy the Infrastructure

Apply the Terraform configuration to create the resources.

```sh
terraform apply
```

You will be prompted to confirm the changes. Type `yes` and press Enter.

#### Step 5: Access Outputs

After the infrastructure is created, you can access the outputs defined in `outputs.tf`. For example, to get the OpenSearch endpoint:

```sh
terraform output aws_opensearch_domain
```

#### Cleanup

To destroy all resources created by this Terraform configuration, run:

```sh
terraform destroy
```

Confirm the action by typing `yes` when prompted.

### Scripts
