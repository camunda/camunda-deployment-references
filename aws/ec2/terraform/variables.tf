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
    values = ["x86_64"]
  }
}

# It's recommended to pin the AMI as otherwise it will result in recreations and wipe everything.
variable "aws_ami" {
  type        = string
  description = "The AMI to use for the EC2 instances if empty, the latest Debian 12 AMI will be used"
  default     = ""
}

variable "aws_instance_type" {
  type        = string
  description = "The instance type to use for the EC2 instances"
  default     = "m5.xlarge"
}

variable "aws_instance_type_bastion" {
  type        = string
  description = "The instance type to use for the bastion host"
  default     = "t2.nano"
}

variable "prefix" {
  type        = string
  description = "The prefix to use for all resources"
  default     = "camunda"
}

variable "instance_count" {
  type        = number
  default     = 3
  description = "The number of instances to create"
}

variable "cidr_blocks" {
  type        = string
  default     = "10.200.0.0/16"
  description = "The CIDR block to use for the VPC"
}

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

# Audit logs are only possible with advanced security options
variable "opensearch_log_types" {
  type        = list(string)
  default     = ["SEARCH_SLOW_LOGS", "INDEX_SLOW_LOGS", "ES_APPLICATION_LOGS"]
  description = "The types of logs to publish to CloudWatch Logs"
}

variable "pub_key_path" {
  type        = string
  description = "The path to the public key to use for the EC2 instances for SSH access"
  default     = "~/.ssh/id_rsa.pub"
}

variable "delete_on_termination" {
  type        = bool
  default     = true
  description = "Delete the root volume on termination of an EC2 instance"
}
