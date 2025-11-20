################################################################
#                        ECS Configs                           #
################################################################

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
}

variable "ecs_cluster_id" {
  description = "The cluster id of the ECS cluster to spawn the ECS service in"
  type        = string
}

variable "vpc_id" {
  description = "The VPC id where the ECS cluster and service are deployed"
  type        = string
}

variable "vpc_private_subnets" {
  description = "List of private subnet IDs within the VPC"
  type        = list(string)
}

variable "vpc_public_subnets" {
  description = "List of public subnet IDs within the VPC"
  type        = list(string)
}

variable "environment_variables" {
  description = "List of environment variable name-value pairs to set in the ECS task"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "service_security_group_ids" {
  description = "List of security group IDs to associate with the ECS service"
  type        = list(string)
  default     = []
}

variable "efs_security_group_ids" {
  description = "List of security group IDs to associate with the EFS file system"
  type        = list(string)
  default     = []
}

variable "task_cpu" {
  description = "The amount of cpu to allocate to the ECS task"
  type        = number
  default     = 4096
}

variable "task_memory" {
  description = "The amount of memory to allocate to the ECS task"
  type        = number
  default     = 8192
}

variable "task_desired_count" {
  description = "The desired count of ECS tasks to run in the ECS service"
  type        = number
  default     = 3
}

variable "task_enable_execute_command" {
  description = "Whether to enable execute command for the ECS service"
  type        = bool
  default     = true
}

variable "prefix" {
  description = "The prefix to use for naming resources"
  type        = string
}

variable "alb_arn" {
  description = "The ARN of the Application Load Balancer to use"
  type        = string
  default     = ""
}

variable "nlb_arn" {
  description = "The ARN of the Network Load Balancer to use"
  type        = string
  default     = ""
}

variable "registry_credentials_arn" {
  description = "The ARN of the Secrets Manager secret containing registry credentials"
  type        = string
  default     = ""
}

variable "extra_task_role_attachments" {
  description = "List of additional IAM policy ARNs to attach to the ECS task role"
  type        = list(string)
  default     = []
}

variable "service_force_new_deployment" {
  description = "Whether to force a new deployment of the ECS service"
  type        = bool
  default     = true
}

################################################################
#                      Camunda Configs                         #
################################################################

variable "image" {
  description = "The container image to use for the Camunda orchestration cluster"
  type        = string
  default     = "camunda/camunda:SNAPSHOT"
}
