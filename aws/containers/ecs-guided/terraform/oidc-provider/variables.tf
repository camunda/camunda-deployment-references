variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

################################################################
#                  Inputs from the network stage               #
################################################################

variable "vpc_id" {
  type        = string
  description = "Network stage output: ID of the VPC"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Network stage output: private subnet IDs"
}

################################################################
#                  Inputs from the compute stage               #
################################################################

variable "ecs_cluster_id" {
  type        = string
  description = "Compute stage output: ID of the ECS cluster that runs the OIDC provider"
}

variable "task_execution_role_arn" {
  type        = string
  description = "Compute stage output: ARN of the task execution role"
}

variable "task_execution_role_name" {
  type        = string
  description = "Compute stage output: name of the task execution role, to attach the secret read policy of this stage"
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Compute stage output: KMS key that encrypts the secrets"
}

variable "registry_credentials_arn" {
  type        = string
  default     = ""
  description = "Compute stage output: registry credentials secret, empty for public images"
}

variable "camunda_ports_security_group_id" {
  type        = string
  description = "Compute stage output: security group that opens the ports inside the VPC"
}

variable "egress_security_group_id" {
  type        = string
  description = "Compute stage output: security group that allows outbound HTTP and HTTPS"
}

variable "service_connect_namespace_arn" {
  type        = string
  description = "Compute stage output: Service Connect namespace shared by the management plane components"
}

variable "log_group_name" {
  type        = string
  description = "Compute stage output components_log_group_name"
}

################################################################
#                 Inputs from the exposure stage               #
################################################################

variable "alb_listener_http_webapp_arn" {
  type        = string
  description = "Exposure stage output: listener the OIDC provider attaches its rule to"
}

variable "public_base_url" {
  type        = string
  description = "Exposure stage output: browser-facing base URL of the load balancer that serves the management plane. The issuer is <public_base_url>/auth/realms/camunda-platform."
}

################################################################
#                 Inputs from the storage stage                #
################################################################

variable "database" {
  type = object({
    database_name       = string
    username            = string
    jdbc_url            = string
    password_secret_arn = string
  })
  description = "Storage stage output databases[\"oidc_provider\"], declared with auth = password"

  validation {
    condition     = var.database.password_secret_arn != ""
    error_message = "The OIDC provider connects with a password: declare its database with auth = password in the storage stage."
  }
}

variable "db_seed_done" {
  type        = string
  default     = ""
  description = "Storage stage output: changes once the database exists. Only used to order the deployment."
}

################################################################
#                      What the realm holds                    #
################################################################

variable "clusters" {
  type = map(object({
    base_url = optional(string, "")
  }))
  default     = { default = {} }
  description = "The Orchestration Clusters that use this provider, by name. Each gets its own orchestration and connectors clients. base_url is the public URL of the cluster, for the login redirect; empty uses public_base_url, which is right when the cluster shares the load balancer. The realm is imported when the provider starts for the first time: a cluster that you add later is registered in the provider's administration console with the values of the clusters output."

  validation {
    condition     = length(var.clusters) >= 1 && alltrue([for k, c in var.clusters : can(regex("^[a-z][a-z0-9-]{0,30}$", k))])
    error_message = "clusters needs at least one entry, named with lowercase letters, digits, and hyphens."
  }
}

variable "enable_camunda_hub" {
  type        = bool
  default     = false
  description = "Register the Camunda Hub client in the realm"
}

variable "hub_context_path" {
  type        = string
  default     = "/hub"
  description = "Context path Camunda Hub is served under. The login redirect is built from it."
}

variable "identity_context_path" {
  type        = string
  default     = "/identity"
  description = "Context path Management Identity is served under. Its login redirect is built from it."
}

variable "service_connect_name" {
  type        = string
  default     = "oidc-provider"
  description = "Name under which the other components of the management plane reach the provider inside the ECS cluster"
}

variable "admin_username" {
  type        = string
  default     = "admin"
  description = "Login user of the realm. It is the administrator of the platform: its username claim receives the admin roles."
}
