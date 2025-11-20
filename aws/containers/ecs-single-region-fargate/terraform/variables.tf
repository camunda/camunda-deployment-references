################################################################
#                        Global Options                        #
################################################################

variable "prefix" {
  type        = string
  description = "The prefix to use for names of resources"
  default     = "camunda"
}

variable "registry_username" {
  type        = string
  description = "(Optional) The username for the container registry (e.g., Docker Hub)"
  default     = ""
}

variable "registry_password" {
  type        = string
  description = "(Optional) The password for the container registry (e.g., Docker Hub)"
  default     = ""
}

################################################################
#                       Network Options                        #
################################################################

variable "cidr_blocks" {
  type        = string
  default     = "10.200.0.0/24"
  description = "The CIDR block to use for the VPC"
}

################################################################
#                      Security Options                        #
################################################################

variable "limit_access_to_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer"
}

variable "ports" {
  type = map(number)
  default = {
    camunda_web_ui                        = 8080
    camunda_metrics_endpoint              = 9600
    connectors_port                       = 9090
    zeebe_gateway_cluster_port            = 26502
    zeebe_gateway_network_port            = 26500
    zeebe_broker_network_command_api_port = 26501
  }
  description = "The ports to open for the security groups within the VPC"
}
