variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

variable "region_a" {
  type        = string
  description = "Region of the first deployment (the existing one)"
}

variable "region_b" {
  type        = string
  description = "Region of the second deployment"
}

# Both sides take the outputs of their network stage.

variable "vpc_id_a" {
  type        = string
  description = "Network stage output in region_a: VPC ID"
}

variable "vpc_cidr_a" {
  type        = string
  description = "Network stage output in region_a: VPC CIDR"
}

variable "private_subnet_ids_a" {
  type        = list(string)
  description = "Network stage output in region_a: private subnet IDs (the DNS resolver endpoints use two of them)"
}

variable "private_route_table_ids_a" {
  type        = list(string)
  description = "Network stage output in region_a: private route table IDs, which get a route to region_b"
}

variable "vpc_id_b" {
  type        = string
  description = "Network stage output in region_b: VPC ID"
}

variable "vpc_cidr_b" {
  type        = string
  description = "Network stage output in region_b: VPC CIDR"
}

variable "private_subnet_ids_b" {
  type        = list(string)
  description = "Network stage output in region_b: private subnet IDs"
}

variable "private_route_table_ids_b" {
  type        = list(string)
  description = "Network stage output in region_b: private route table IDs, which get a route to region_a"
}

variable "enable_dns_resolver" {
  type        = bool
  default     = true
  description = "Forward the service discovery domain of each region to the other through Route 53 Resolver, so that a name registered in one region resolves in the other."
}

variable "service_discovery_domain_a" {
  type        = string
  default     = ""
  description = "Service discovery domain of the deployment in region_a: <prefix of its camunda stage>-oc.service.local. Required with enable_dns_resolver."
}

variable "service_discovery_domain_b" {
  type        = string
  default     = ""
  description = "Service discovery domain of the deployment in region_b. Required with enable_dns_resolver."
}
