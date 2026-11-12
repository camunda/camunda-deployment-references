variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

variable "vpc_id" {
  type        = string
  description = "Network stage output: ID of the VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "Network stage output: CIDR block of the VPC, used for the intra-VPC security group rules"
}

variable "additional_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks of other VPCs, for example the second region, allowed on the same Camunda ports. Empty for a single region."
}

variable "ports" {
  type = map(number)
  default = {
    postgresql                            = 5432
    camunda_web_ui                        = 8080
    camunda_metrics_endpoint              = 9600
    zeebe_gateway_cluster_port            = 26502
    zeebe_gateway_network_port            = 26500
    zeebe_broker_network_command_api_port = 26501
  }
  description = "Ports opened between the tasks and the database inside the VPC"
}

variable "management_plane_ports" {
  type = map(number)
  default = {
    management_identity_app        = 8084
    management_identity_management = 8082
    oidc_provider_http             = 18080
    oidc_provider_management       = 9000
    camunda_hub_restapi            = 8081
    camunda_hub_management         = 8091
    camunda_hub_websockets         = 8060
  }
  description = "Ports of the management plane components (OIDC provider, Management Identity, Camunda Hub), opened inside the VPC when enable_management_plane is true"
}

variable "enable_management_plane" {
  type        = bool
  default     = false
  description = "Open the ports of the management plane components in the shared security group. Set it in the compute stage that hosts the OIDC provider, Management Identity, and Camunda Hub."
}

variable "registry_username" {
  type        = string
  default     = ""
  description = "Username for a private image registry. Leave empty when the images are public."
}

variable "registry_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Password for a private image registry"
}

variable "secrets_kms_key_arn" {
  type        = string
  default     = ""
  description = "Existing KMS key to encrypt Secrets Manager secrets with. When empty, this stage creates one and every later stage uses it."
}
