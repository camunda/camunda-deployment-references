variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

################################################################
#                  Inputs from the network layer               #
################################################################

variable "vpc_id" {
  type        = string
  description = "Network layer output: ID of the VPC"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Network layer output: private subnet IDs"
}

################################################################
#                  Inputs from the compute layer               #
################################################################

variable "ecs_cluster_id" {
  type        = string
  description = "Compute layer output: ID of the ECS cluster"
}

variable "task_execution_role_arn" {
  type        = string
  description = "Compute layer output: ARN of the task execution role"
}

variable "task_execution_role_name" {
  type        = string
  description = "Compute layer output: name of the task execution role, to attach the secret read policy of this layer"
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Compute layer output: KMS key that encrypts the secrets"
}

variable "registry_credentials_arn" {
  type        = string
  default     = ""
  description = "Compute layer output: registry credentials secret, empty for public images"
}

variable "camunda_ports_security_group_id" {
  type        = string
  description = "Compute layer output: security group that opens the ports inside the VPC"
}

variable "egress_security_group_id" {
  type        = string
  description = "Compute layer output: security group that allows outbound HTTP and HTTPS"
}

variable "service_connect_namespace_arn" {
  type        = string
  description = "Compute layer output: Service Connect namespace shared by the management plane components"
}

variable "log_group_name" {
  type        = string
  description = "Compute layer output components_log_group_name"
}

################################################################
#                 Inputs from the exposure layer               #
################################################################

variable "alb_listener_http_webapp_arn" {
  type        = string
  description = "Exposure layer output: listener Management Identity attaches its rule to"
}

variable "public_base_url" {
  type        = string
  description = "Exposure layer output: browser-facing base URL"
}

################################################################
#                 Inputs from the storage layer                #
################################################################

variable "database" {
  type = object({
    database_name      = string
    username           = string
    jdbc_url           = string
    connect_policy_arn = string
  })
  description = "Storage layer output databases[\"management_identity\"], declared with auth = iam"

  validation {
    condition     = var.database.connect_policy_arn != ""
    error_message = "Management Identity connects with an IAM token: declare its database with auth = iam in the storage layer."
  }
}

variable "db_seed_done" {
  type        = string
  default     = ""
  description = "Storage layer output: changes once the database exists. Only used to order the deployment."
}

################################################################
#               Input from the OIDC provider layer             #
################################################################

variable "oidc" {
  type = object({
    issuer_uri         = string
    issuer_backend_uri = string
    username_claim     = string
    admin_claim        = string
    identity = object({
      client_id         = string
      client_secret_arn = string
      audience          = string
    })
    hub = object({
      client_id         = string
      audience_internal = string
      audience_public   = string
    })
  })
  description = "OIDC provider layer output management. It can also describe an OIDC provider that you run yourself, as long as it has the client that identity names and the audiences."
}

################################################################
#                       Configuration                          #
################################################################

variable "context_path" {
  type        = string
  default     = "/identity"
  description = "Context path Management Identity is served under on the load balancer"
}

variable "enable_hub_authorization" {
  type        = bool
  default     = false
  description = "Declare the roles Camunda Hub needs (Web Modeler, Web Modeler Admin) and grant them to the administrator. Turn it on when Camunda Hub uses this Management Identity: without it Hub signs in, but every authorization check is denied."
}
