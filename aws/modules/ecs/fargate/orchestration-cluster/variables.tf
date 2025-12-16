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

variable "task_enable_execute_command" {
  description = "Whether to enable execute command for the ECS service"
  type        = bool
  default     = true
}

variable "prefix" {
  description = "The prefix to use for naming resources"
  type        = string
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

variable "extra_service_role_attachments" {
  description = "List of additional IAM policy ARNs to attach to the ECS service role"
  type        = list(string)
  default     = []
}

variable "service_force_new_deployment" {
  description = "Whether to force a new deployment of the ECS service"
  type        = bool
  default     = false
}

variable "cloudwatch_retention_days" {
  description = "The number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "efs_throughput_mode" {
  description = "The throughput mode for the EFS file system"
  type        = string
  default     = "provisioned"
}

variable "efs_provisioned_throughput_in_mibps" {
  description = "The provisioned throughput in MiB/s for the EFS file system if using provisioned mode"
  type        = number
  default     = 125
}

variable "efs_performance_mode" {
  description = "The performance mode for the EFS file system"
  type        = string
  default     = "generalPurpose"
}

variable "alb_listener_http_80_arn" {
  description = "The ARN of the ALB listener for HTTP on port 80"
  type        = string
  default     = ""
}

variable "alb_listener_http_9600_arn" {
  description = "The ARN of the ALB listener for HTTP on port 9600"
  type        = string
  default     = ""
}

variable "wait_for_steady_state" {
  description = "Whether to wait for the ECS service to reach a steady state after deployment"
  type        = bool
  default     = true
}

variable "service_timeouts" {
  description = "Timeout configuration for ECS service operations"
  type = object({
    create = optional(string, "30m")
    update = optional(string, "30m")
    delete = optional(string, "20m")
  })
  default = {
    create = "30m"
    update = "30m"
    delete = "20m"
  }
}

################################################################
#                      Camunda Configs                         #
################################################################

variable "image" {
  description = "The container image to use for the Camunda orchestration cluster"
  type        = string
  default     = "camunda/camunda:SNAPSHOT"
}

variable "environment_variables" {
  description = "List of environment variable name-value pairs to set in the ECS task"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "task_desired_count" {
  description = "The desired count of ECS tasks to run in the ECS service - directly impacts the Zeebe cluster size"
  type        = number
  default     = 3
}
