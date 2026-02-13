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
  default     = 900
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
  default     = 50
}

variable "efs_performance_mode" {
  description = "The performance mode for the EFS file system"
  type        = string
  default     = "generalPurpose"
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

variable "alb_listener_http_management_arn" {
  description = "The ARN of the ALB listener for the management port HTTP(s) traffic"
  type        = string
  default     = ""
}

variable "enable_alb_http_management_listener_rule" {
  description = "Whether to create the ALB listener rule for the management port (must be a known boolean at plan time)"
  type        = bool
  default     = false
}

check "monitoring_port_9600_exposure" {
  assert {
    condition     = !var.enable_alb_http_management_listener_rule
    error_message = "enable_alb_http_9600_listener_rule is true. The management port (9600) should not be exposed without intent, as it is not secured by default. Consider using a temporary jump host, Lambda, Step Functions or a VPN connected to the VPC to access it securely."
  }
}

variable "enable_nlb_grpc_26500_listener" {
  description = "Whether to create the NLB listener on port 26500 (must be a known boolean at plan time)"
  type        = bool
  default     = true
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
  # TODO: [release-duty] before the release, update the below versions to the stable release!
  # TODO: [release-duty] adjust renovate comment to bump the minor version to the new stable release
  # renovate: datasource=docker depName=camunda/camunda versioning=regex:^8\.9?(\.(?<patch>\d+))?$
  default = "camunda/camunda:8.9.0-alpha4"
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

################################################################
#                 Restore Init Container                       #
################################################################

variable "restore_backup_id" {
  description = "The backup ID to restore from. When set, enables the restore init container that runs before the main container."
  type        = string
  default     = ""
}

variable "restore_container_image" {
  description = "Container image for the restore init container. Required when restore_backup_id is set."
  type        = string
  # TODO: [release-duty] before the release, update the below versions to the stable release!
  # TODO: [release-duty] adjust renovate comment to bump the minor version to the new stable release
  # renovate: datasource=docker depName=camunda/camunda versioning=regex:^8\.9?(\.(?<patch>\d+))?$
  default = "camunda/camunda:8.9.0-alpha4"
}

variable "restore_container_entrypoint" {
  description = "Entrypoint for the restore init container (Docker ENTRYPOINT). Defaults to the restore application."
  type        = list(string)
  default = [
    "bash",
    "-c",
    "/usr/local/camunda/bin/restore --backupId=$BACKUP_ID"
  ]
}

variable "restore_container_secrets" {
  description = "ECS task secrets for the restore init container (rendered as container definition 'secrets')."
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "task_desired_count" {
  description = "The desired count of ECS tasks to run in the ECS service - directly impacts the Zeebe cluster size"
  type        = number
  default     = 3
}

variable "s3_force_destroy" {
  description = "Whether to force destroy the S3 bucket even if it contains objects. Set to true for dev/test environments."
  type        = bool
  default     = false
}
