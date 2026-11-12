variable "prefix" {
  type        = string
  description = "Name prefix of the resources"
}

variable "byo_vpc" {
  type        = bool
  default     = false
  description = "Use an existing VPC instead of creating one. Requires vpc_id, vpc_cidr and private_subnet_ids."
}

variable "cidr" {
  type        = string
  default     = "10.190.0.0/16"
  description = "CIDR block of the VPC to create"
}

variable "az_count" {
  type        = number
  default     = 3
  description = "Number of availability zones to use when creating a VPC (at least 3)"
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "Use a single shared NAT gateway instead of one per zone"
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "BYO: ID of the existing VPC"
}

variable "vpc_cidr" {
  type        = string
  default     = ""
  description = "BYO: CIDR block of the existing VPC"
}

variable "private_subnet_ids" {
  type        = list(string)
  default     = []
  description = "BYO: at least 3 private subnet IDs in distinct availability zones"
}

variable "public_subnet_ids" {
  type        = list(string)
  default     = []
  description = "BYO: at least 3 public subnet IDs in distinct availability zones, for internet-facing load balancers"
}

variable "private_route_table_ids" {
  type        = list(string)
  default     = []
  description = "BYO: private route table IDs, only needed for peering or transit gateway routes later"
}
