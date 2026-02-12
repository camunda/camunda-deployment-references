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
  default     = 2048
}

variable "task_memory" {
  description = "The amount of memory to allocate to the ECS task"
  type        = number
  default     = 4096
}

variable "task_enable_execute_command" {
  description = "Whether to enable execute command for the ECS service"
  type        = bool
  default     = false
}

variable "task_operating_system_family" {
  description = "The operating system family to use for the ECS task"
  type        = string
  default     = "LINUX"
}

variable "task_cpu_architecture" {
  description = "The CPU architecture to use for the ECS task"
  type        = string
  default     = "X86_64"
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

variable "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role (centrally managed)"
  type        = string
}

variable "service_force_new_deployment" {
  description = "Whether to force a new deployment of the ECS service"
  type        = bool
  default     = false
}

variable "service_health_check_grace_period_seconds" {
  description = "Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown"
  type        = number
  default     = 300
}

variable "s2s_cloudmap_namespace" {
  description = "The ARN of the Service Connect namespace for service-to-service communication"
  type        = string
  default     = ""
}

variable "alb_listener_http_webapp_arn" {
  description = "The ARN of the ALB listener for the web application port HTTP(s) traffic"
  type        = string
  default     = ""
}

variable "enable_alb_http_webapp_listener_rule" {
  description = "Whether to create the ALB listener rule for the WebApp (must be a known boolean at plan time)"
  type        = bool
  default     = true
}

variable "log_group_name" {
  description = "The name of the CloudWatch log group for the ECS tasks"
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
  description = "The container image to use for the Camunda Connectors"
  type        = string
  # TODO: [release-duty] before the release, update the below versions to the stable release!
  # TODO: [release-duty] adjust renovate comment to bump the minor version to the new stable release
  # renovate: datasource=docker depName=camunda/connectors-bundle versioning=regex:^8\.9?(\.(?<patch>\d+))?$
  default = "camunda/connectors-bundle:8.9.0-alpha3"
}

variable "environment_variables" {
  description = "List of environment variable name-value pairs to set in the ECS task"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secrets" {
  description = "List of ECS task secrets to expose to the container (rendered as container definition 'secrets'). Each item must be { name = string, valueFrom = string } where valueFrom is typically a Secrets Manager secret ARN."
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "init_container_enabled" {
  description = "Whether to add an init container that must complete successfully before the main container starts."
  type        = bool
  default     = false
}

variable "init_container_name" {
  description = "Name of the init container (referenced by dependsOn)."
  type        = string
  default     = "init"
}

variable "init_container_image" {
  description = "Container image for the init container."
  type        = string
  default     = ""
}

variable "init_container_command" {
  description = "Command for the init container (Docker CMD). If empty, uses the image default."
  type        = list(string)
  default     = []
}

variable "init_container_environment_variables" {
  description = "Environment variables for the init container."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "init_container_secrets" {
  description = "ECS task secrets for the init container (rendered as container definition 'secrets')."
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "task_desired_count" {
  description = "The desired count of ECS tasks to run in the ECS service - directly impacts the Zeebe cluster size"
  type        = number
  default     = 1
}
