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

variable "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role (centrally managed)"
  type        = string
}

variable "prefix" {
  description = "The prefix to use for naming resources"
  type        = string
}

variable "task_cpu" {
  description = "The amount of cpu to allocate to the ECS task"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "The amount of memory to allocate to the ECS task"
  type        = number
  default     = 1024
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

variable "service_force_new_deployment" {
  description = "Whether to force a new deployment of the ECS service"
  type        = bool
  default     = false
}

variable "wait_for_steady_state" {
  description = "Whether to wait for the ECS service to reach a steady state after deployment"
  type        = bool
  default     = true
}

variable "service_timeouts" {
  description = "Timeout configuration for ECS service operations"
  type = object({
    create = optional(string, "15m")
    update = optional(string, "30m")
    delete = optional(string, "20m")
  })
  default = {
    create = "15m"
    update = "30m"
    delete = "20m"
  }
}

variable "registry_credentials_arn" {
  description = "The ARN of the Secrets Manager secret containing registry credentials, when the images are pulled from a private registry"
  type        = string
  default     = ""
}

################################################################
#                      Logging Configs                         #
################################################################

variable "log_group_name" {
  description = "The name of an existing CloudWatch log group for the ECS tasks. When empty, the module creates its own log group."
  type        = string
  default     = ""
}

variable "log_retention_in_days" {
  description = "Retention of the CloudWatch log group created by this module. Ignored when log_group_name is supplied."
  type        = number
  default     = 7
}

################################################################
#                     Prometheus Configs                       #
################################################################

variable "image" {
  description = "The container image to use for Prometheus"
  type        = string
  # renovate: datasource=docker depName=prom/prometheus
  default = "prom/prometheus:v3.11.2"
}

variable "prometheus_port" {
  description = "The port Prometheus listens on"
  type        = number
  default     = 9090

  validation {
    condition     = var.prometheus_port > 0 && var.prometheus_port < 65536
    error_message = "prometheus_port must be a valid TCP port between 1 and 65535."
  }
}

variable "retention_time" {
  description = "How long Prometheus keeps samples on local storage, as a Prometheus duration (for example 168h, 15d, 4w)."
  type        = string
  default     = "168h"

  validation {
    condition     = can(regex("^[0-9]+(ms|s|m|h|d|w|y)$", var.retention_time))
    error_message = "retention_time must be a Prometheus duration such as 168h, 15d or 4w."
  }
}

variable "scrape_interval" {
  description = "The global Prometheus scrape interval, as a Prometheus duration."
  type        = string
  default     = "15s"

  validation {
    condition     = can(regex("^[0-9]+(ms|s|m|h|d|w|y)$", var.scrape_interval))
    error_message = "scrape_interval must be a Prometheus duration such as 15s or 1m."
  }
}

################################################################
#                      Discovery Configs                       #
################################################################

variable "discovery_image" {
  description = "The container image used by the Cloud Map discovery sidecar. It only needs the AWS CLI."
  type        = string
  # renovate: datasource=docker depName=amazon/aws-cli
  default = "amazon/aws-cli:2.32.7"
}

variable "discovery_namespace_suffix" {
  description = "Only Cloud Map private DNS namespaces whose name ends with this suffix are scraped. The orchestration-cluster module registers '<prefix>.service.local'."
  type        = string
  default     = ".service.local"

  validation {
    condition     = length(var.discovery_namespace_suffix) > 0
    error_message = "discovery_namespace_suffix must not be empty: an empty suffix would match every private DNS namespace in the account."
  }
}

variable "discovery_service_name" {
  description = "The Cloud Map service name to look for inside each matching namespace."
  type        = string
  default     = "orchestration-cluster"

  validation {
    condition     = length(var.discovery_service_name) > 0
    error_message = "discovery_service_name must not be empty."
  }
}

variable "discovery_refresh_interval_seconds" {
  description = "How often the sidecar re-queries Cloud Map. Prometheus hot-reloads the file it writes, so this is also how quickly a new cluster starts being scraped."
  type        = number
  default     = 30

  validation {
    condition     = var.discovery_refresh_interval_seconds > 0
    error_message = "discovery_refresh_interval_seconds must be greater than zero."
  }
}

variable "metrics_port" {
  description = "The port the discovered targets expose their metrics on. Matches the Camunda management port."
  type        = number
  default     = 9600

  validation {
    condition     = var.metrics_port > 0 && var.metrics_port < 65536
    error_message = "metrics_port must be a valid TCP port between 1 and 65535."
  }
}

variable "metrics_path" {
  description = "The HTTP path the discovered targets expose their metrics on."
  type        = string
  default     = "/actuator/prometheus"
}

################################################################
#                    Load Balancer Configs                     #
################################################################

variable "enable_alb_http_listener_rule" {
  description = "Whether to expose Prometheus through an existing ALB listener. Off by default: the endpoint is unauthenticated, so it stays reachable only from inside the VPC unless you opt in."
  type        = bool
  default     = false
}

variable "alb_listener_http_arn" {
  description = "The ARN of the ALB listener to attach the Prometheus rule to. Required when enable_alb_http_listener_rule is true."
  type        = string
  default     = ""
}

variable "alb_listener_rule_priority" {
  description = "The priority of the ALB listener rule created for Prometheus."
  type        = number
  default     = 100
}

variable "alb_listener_rule_path_pattern" {
  description = "The path pattern the ALB listener rule matches on."
  type        = string
  default     = "/prometheus/*"
}
