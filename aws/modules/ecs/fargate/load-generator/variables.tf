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
  description = "ARN of the ECS task execution role (centrally managed). It must be allowed to read auth_password_secret_arn."
  type        = string
}

variable "prefix" {
  description = "The prefix to use for naming resources"
  type        = string
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

variable "task_desired_count" {
  description = "How many load generator tasks to run. Each one produces start_rate process instances per second, so the total rate is the product of the two."
  type        = number
  default     = 1

  validation {
    condition     = var.task_desired_count >= 0
    error_message = "task_desired_count must be zero or more. Zero parks the service without destroying it."
  }
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
  description = "Whether to force a new deployment of the ECS service. Set it to restart the generator without changing its configuration."
  type        = bool
  default     = false
}

variable "wait_for_steady_state" {
  description = "Whether to wait for the ECS service to reach a steady state after deployment"
  type        = bool
  default     = false
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
  description = "The ARN of the Secrets Manager secret containing registry credentials, when the image is pulled from a private registry. Not needed for the default public image."
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

variable "log_level" {
  description = "Root log level of the generator. The throughput lines it prints are INFO."
  type        = string
  default     = "INFO"
}

################################################################
#                    Camunda Client Configs                    #
################################################################

variable "image" {
  description = "The container image used to generate load. Defaults to the community benchmark project, which is publicly pullable; the Camunda reliability-testing images are not."
  type        = string
  default     = "camundacommunityhub/camunda-8-benchmark:main"
}

variable "camunda_host" {
  description = "Hostname of the Orchestration Cluster to drive load against, typically the Cloud Map record of the orchestration-cluster module (orchestration-cluster.<prefix>.service.local)."
  type        = string

  validation {
    condition     = length(var.camunda_host) > 0
    error_message = "camunda_host must not be empty."
  }
}

variable "camunda_grpc_port" {
  description = "The gRPC port of the Orchestration Cluster gateway"
  type        = number
  default     = 26500
}

variable "camunda_rest_port" {
  description = "The REST port of the Orchestration Cluster gateway"
  type        = number
  default     = 8080
}

variable "prefer_rest_over_grpc" {
  description = "Whether the client should prefer the REST API over gRPC"
  type        = bool
  default     = false
}

variable "auth_method" {
  description = "How the generator authenticates against the Orchestration Cluster. The ECS reference deploys no Management Identity, so it runs basic auth."
  type        = string
  default     = "basic"

  validation {
    condition     = contains(["basic", "none", "oidc"], var.auth_method)
    error_message = "auth_method must be one of: basic, none, oidc."
  }
}

variable "auth_username" {
  description = "Username used when auth_method is basic"
  type        = string
  default     = "demo"
}

variable "auth_password_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the password. Required when auth_method is basic. Passed as an ECS secret so it never appears in the task definition."
  type        = string
  default     = ""
}

################################################################
#                      Benchmark Configs                       #
################################################################

variable "start_rate" {
  description = "Process instances started per second, per task."
  type        = number
  default     = 10

  validation {
    condition     = var.start_rate > 0
    error_message = "start_rate must be greater than zero."
  }
}

variable "rate_adjustment_strategy" {
  description = "How the generator reacts when the cluster slows down. 'none' holds a fixed rate, which is what makes a throughput dip visible instead of absorbed."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "backpressure", "responsetime"], var.rate_adjustment_strategy)
    error_message = "rate_adjustment_strategy must be one of: none, backpressure, responsetime."
  }
}

variable "start_workers" {
  description = "Whether to run job workers alongside the starter. Without them instances pile up as active work and the export rate stops tracking the start rate."
  type        = bool
  default     = true
}

variable "job_type" {
  description = "The job type the workers subscribe to. Must match the service tasks in the deployed process."
  type        = string
  default     = "benchmark-task"
}

variable "multiple_job_types" {
  description = "Number of job types, derived by suffixing job_type with 1..N. Must equal the number of service tasks in the process, or instances get stuck on a task nothing subscribes to."
  type        = number
  default     = 1

  validation {
    condition     = var.multiple_job_types >= 1
    error_message = "multiple_job_types must be at least 1."
  }
}

variable "task_completion_delay" {
  description = "Milliseconds a worker waits before completing a job, standing in for real work."
  type        = number
  default     = 50
}

variable "warmup_phase_duration_millis" {
  description = "Milliseconds of warm-up before the generator holds its target rate."
  type        = number
  default     = 10000
}

variable "auto_deploy_process" {
  description = "Whether the generator deploys its process definition on startup."
  type        = bool
  default     = true
}

variable "bpmn_process_id" {
  description = "Process id to start. Leave empty to use the image's built-in benchmark process."
  type        = string
  default     = ""
}

variable "bpmn_resource" {
  description = "Location of the process definition to deploy, for example 'classpath:bpmn/one_task.bpmn'. Leave empty to use the image default; ECS has no ConfigMap equivalent, so a custom file needs a volume you mount yourself."
  type        = string
  default     = ""
}

variable "extra_environment_variables" {
  description = "Additional environment variables appended to the container definition, for benchmark settings this module does not surface."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}
