################################################################
#                         Data Sources                         #
################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"] # Debian
  filter {
    name   = "name"
    values = ["debian-12-*"]
  }

  filter {
    name   = "architecture"
    values = [var.aws_instance_architecture]
  }
}

################################################################
#                        Feature Flags                         #
################################################################

variable "enable_jump_host" {
  type        = bool
  default     = true
  description = "Enable the jump host (bastion) to access the private instances"
}

variable "enable_opensearch" {
  type        = bool
  default     = true
  description = "Enable the OpenSearch cluster. If false, the OpenSearch cluster will not be created. Users may want to supply DBs manually themselves."
}

variable "enable_alb" {
  type        = bool
  default     = true
  description = "Enable the Application Load Balancer. If false, the ALB will not be created, e.g. if a user doesn't want to publicy expose the setup."
}

variable "enable_nlb" {
  type        = bool
  default     = true
  description = "Enable the Network Load Balancer. If false, the NLB will not be created."
}

variable "enable_vpc_logging" {
  type        = bool
  default     = false
  description = "Enable VPC flow logging to CloudWatch Logs"
}

variable "enable_opensearch_logging" {
  type        = bool
  default     = false
  description = "Enable OpenSearch logging to CloudWatch Logs"
}

variable "generate_ssh_key_pair" {
  type        = bool
  default     = false
  description = "Generate an SSH key pair for the EC2 instances over the use of pub_key_path. Meant for testing purposes / temp environments."
}

################################################################
#                        Global Options                        #
################################################################

variable "prefix" {
  type        = string
  description = "The prefix to use for names of resources"
  default     = "camunda"
}

################################################################
#                       Instance Options                       #
################################################################

variable "instance_count" {
  type        = number
  default     = 3
  description = "The number of instances to create"
}

# It's recommended to pin the AMI as otherwise it will result in recreations and wipe everything.
variable "aws_ami" {
  type        = string
  description = "The AMI to use for the EC2 instances if empty, the latest Debian 12 AMI will be used"
  default     = ""
}

variable "aws_instance_type" {
  type        = map(string)
  description = "The instance type to use for the EC2 instances based on the architecture"
  default = {
    x86_64 = "m7i.xlarge"
    arm64  = "m7g.xlarge"
  }
}

variable "aws_instance_type_bastion" {
  type        = map(string)
  description = "The instance type to use for the bastion host based on the architecture"
  default = {
    x86_64 = "t3.nano"
    arm64  = "t4g.nano"
  }
}

variable "aws_instance_architecture" {
  type        = string
  description = "The architecture of the AMI to use for the EC2 instances. Available options: x86_64, arm64"
  default     = "x86_64"
}

variable "camunda_disk_size" {
  type        = number
  default     = 50
  description = "The size of the Camunda disk in GiB"
}

variable "pub_key_path" {
  type        = string
  description = "The path to the public key to use for the EC2 instances for SSH access"
  default     = "~/.ssh/id_rsa.pub"
}

################################################################
#                       Network Options                        #
################################################################

variable "cidr_blocks" {
  type        = string
  default     = "10.200.0.0/16"
  description = "The CIDR block to use for the VPC"
}

################################################################
#                      OpenSearch Options                      #
################################################################

# Audit logs are only possible with advanced security options
variable "opensearch_log_types" {
  type        = list(string)
  default     = ["SEARCH_SLOW_LOGS", "INDEX_SLOW_LOGS", "ES_APPLICATION_LOGS"]
  description = "The types of logs to publish to CloudWatch Logs"
}

variable "opensearch_disk_size" {
  type        = number
  default     = 50
  description = "The size of the OpenSearch disk in GiB"
}

variable "opensearch_instance_count" {
  type        = number
  default     = 3
  description = "The number of instances to create"
}

variable "opensearch_engine_version" {
  type = string
  # renovate: datasource=custom.opensearch-camunda depName=opensearch versioning=semver
  default     = "2.15"
  description = "The engine version of the OpenSearch cluster"
}

variable "opensearch_instance_type" {
  type        = map(string)
  description = "The instance type to use for the OpenSearch instances"

  # There's no `medium.search` for non arm64 instances. That's why we align the instance types with the x64 instances.
  default = {
    x86_64 = "m7i.large.search"
    arm64  = "m7g.large.search"
  }
}

variable "opensearch_dedicated_master_type" {
  type        = map(string)
  description = "The instance type to use for the dedicated OpenSearch master nodes"
  default = {
    x86_64 = "m7i.large.search"
    arm64  = "m7g.large.search"
  }
}

variable "opensearch_architecture" {
  type        = string
  description = "The architecture of the AMI to use for the OpenSearch instances. Available options: x86_64, arm64"
  default     = "x86_64"
}

################################################################
#                      Security Options                        #
################################################################

variable "limit_access_to_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer"
}

variable "ports" {
  type = map(number)
  default = {
    ssh                                   = 22
    opensearch_https                      = 443
    camunda_web_ui                        = 8080
    camunda_metrics_endpoint              = 9600
    connectors_port                       = 9090
    zeebe_gateway_cluster_port            = 26502
    zeebe_gateway_network_port            = 26500
    zeebe_broker_network_command_api_port = 26501
  }
  description = "The ports to open for the security groups within the VPC"
}
