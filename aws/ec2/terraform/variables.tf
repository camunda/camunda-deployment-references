data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# TODO: Maybe retrieve the AMI from data source and just supply ubuntu / debian / aws
# Hard coded AMIs disappear quite quickly
variable "aws_ami" {
  type        = string
  description = "The AMI to use for the EC2 instances"
  default     = "ami-0eb11ab33f229b26c" # Debian 12
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
