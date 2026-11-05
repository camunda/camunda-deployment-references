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
  description = "Compute layer output: registry credentials secret. It is only attached to images that come from the private Camunda registry."
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
  description = "Exposure layer output: listener Camunda Hub attaches its rules to"
}

variable "public_base_url" {
  type        = string
  description = "Exposure layer output: browser-facing base URL, for the login redirect and the websocket host"
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
  description = "Storage layer output databases[\"camunda_hub\"], declared with auth = iam"

  validation {
    condition     = var.database.connect_policy_arn != ""
    error_message = "Camunda Hub connects with an IAM token: declare its database with auth = iam in the storage layer."
  }
}

variable "db_seed_done" {
  type        = string
  default     = ""
  description = "Storage layer output: changes once the database exists. Only used to order the deployment."
}

################################################################
#       Inputs from the OIDC provider and Management Identity  #
################################################################

variable "oidc" {
  type = object({
    issuer_uri         = string
    issuer_backend_uri = string
    hub = object({
      client_id         = string
      audience_internal = string
      audience_public   = string
    })
  })
  description = "OIDC provider layer output management. It can also describe an OIDC provider that you run yourself, with a public client for Camunda Hub and the two audiences."
}

variable "management_identity_url" {
  type        = string
  description = "Management Identity layer output internal_url: where Camunda Hub asks for roles and organizations"
}

variable "management_identity_hub_authorization_enabled" {
  type        = bool
  description = "Management Identity layer output hub_authorization_enabled. It must be true: otherwise Camunda Hub signs in but every authorization check is denied."

  validation {
    condition     = var.management_identity_hub_authorization_enabled
    error_message = "Management Identity does not declare the roles of Camunda Hub: set enable_hub_authorization = true in the Management Identity layer."
  }
}

################################################################
#                   Orchestration Clusters                     #
################################################################

variable "clusters" {
  type = map(object({
    name          = optional(string, "")
    version       = string
    rest_url      = string
    grpc_url      = string
    readiness_url = string
  }))
  description = "The Orchestration Clusters that this Camunda Hub connects to, by ID. Take each entry from the cluster_registration output of the Camunda layer of that cluster. One Camunda Hub serves all of them."

  validation {
    condition     = length(var.clusters) >= 1
    error_message = "clusters needs at least one Orchestration Cluster."
  }
}

################################################################
#                         Configuration                        #
################################################################

variable "context_path" {
  type        = string
  default     = "/hub"
  description = "Context path Camunda Hub is served under on the load balancer. The websocket relay is served under <context_path>-ws."
}

variable "camunda_license_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "License key. Stored in Secrets Manager and injected as CAMUNDA_LICENSE_KEY. Empty runs Camunda Hub in its trial mode."
}

variable "mail_from_address" {
  type        = string
  default     = "changeme@example.com"
  description = "Sender address of invitation mails. The application requires one. Without an SMTP host, invitations aren't sent."
}

variable "restapi_image" {
  type = string
  # TODO: [release-duty] before the release, update the below versions to the stable release!
  # renovate: datasource=docker depName=camunda/hub versioning=regex:^8\.10(?:\.(?<patch>\d+))?(?:-alpha(?<prerelease>\d+))?$
  default     = "camunda/hub:8.10.4"
  description = "Image of the Camunda Hub REST API and web UI. Registry credentials are attached only if it comes from registry.camunda.cloud."
}

variable "websockets_image" {
  type = string
  # TODO: [release-duty] before the release, update the below versions to the stable release!
  # renovate: datasource=docker depName=camunda/hub-websockets versioning=regex:^8\.10(?:\.(?<patch>\d+))?(?:-alpha(?<prerelease>\d+))?$
  default     = "camunda/hub-websockets:8.10.4"
  description = "Image of the Camunda Hub websocket relay. Registry credentials are attached only if it comes from registry.camunda.cloud."
}
