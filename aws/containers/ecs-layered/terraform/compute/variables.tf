variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

variable "vpc_id" {
  type        = string
  description = "Network layer output: ID of the VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "Network layer output: CIDR block of the VPC, used for the intra-VPC security group rules"
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
  description = "Existing KMS key to encrypt Secrets Manager secrets with. When empty, this layer creates one and every later layer uses it."
}
