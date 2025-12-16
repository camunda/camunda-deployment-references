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

variable "task_cpu" {
  description = "The amount of cpu to allocate to the ECS task"
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "The amount of memory to allocate to the ECS task"
  type        = number
  default     = 2048
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

variable "s2s_cloudmap_namespace" {
  description = "The ARN of the Service Connect namespace for service-to-service communication"
  type        = string
  default     = ""
}

variable "alb_listener_http_80_arn" {
  description = "The ARN of the ALB listener for HTTP on port 80"
  type        = string
  default     = ""
}

variable "log_group_name" {
  description = "The name of the CloudWatch log group for the ECS tasks"
  type        = string
  default     = ""
}

################################################################
#                      Camunda Configs                         #
################################################################

variable "image" {
  description = "The container image to use for the Camunda orchestration cluster"
  type        = string
  default     = "camunda/connectors-bundle:SNAPSHOT"
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
  default     = 1
}
