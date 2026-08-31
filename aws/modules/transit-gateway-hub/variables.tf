variable "name" {
  description = "Name prefix for the Transit Gateway and its attachment, typically `<cluster_name>-<region_short_name>`"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC hosting the regional Kubernetes cluster"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs used for the Transit Gateway VPC attachment. Use one private subnet per availability zone."
  type        = list(string)
}

variable "vpc_route_table_ids" {
  description = "Route table IDs of the local VPC that must be able to reach the remote regions (main + private route tables)"
  type        = list(string)
}

variable "remote_cidr_blocks" {
  description = "CIDR blocks of every remote region VPC that must be reachable through the Transit Gateway"
  type        = list(string)
  default     = []
}
