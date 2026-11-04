variable "name" {
  type        = string
  description = "Name prefix of the VPC and its resources. Ignored in BYO mode."
  default     = "camunda"
}

variable "byo_vpc" {
  type        = bool
  default     = false
  description = "When true, no VPC is created: the module validates and re-exposes the supplied vpc_id and subnet IDs so that downstream layers consume one contract, whoever built the network."
}

variable "cidr" {
  type        = string
  default     = "10.200.0.0/16"
  description = "CIDR block of the VPC to create. Ignored in BYO mode."
}

variable "az_count" {
  type        = number
  default     = 3
  description = "Number of availability zones (and private/public subnet pairs) to create. Ignored in BYO mode."

  validation {
    condition     = var.az_count >= 3
    error_message = "At least 3 availability zones are required: Camunda brokers and Aurora are spread over three zones."
  }
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "Use one shared NAT gateway instead of one per availability zone. Cheaper, no zone redundancy for egress. Ignored in BYO mode."
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "BYO mode: ID of the existing VPC."

  validation {
    condition     = var.vpc_id == "" || can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must look like vpc-0123abcd."
  }
}

variable "vpc_cidr" {
  type        = string
  default     = ""
  description = "BYO mode: CIDR block of the existing VPC (used for security group rules)."
}

variable "private_subnet_ids" {
  type        = list(string)
  default     = []
  description = "BYO mode: at least 3 private subnet IDs in distinct availability zones (ECS tasks, Aurora)."
}

variable "public_subnet_ids" {
  type        = list(string)
  default     = []
  description = "BYO mode: at least 3 public subnet IDs in distinct availability zones with a route to an internet gateway (internet-facing load balancers). Can stay empty if nothing is exposed publicly."
}

variable "private_route_table_ids" {
  type        = list(string)
  default     = []
  description = "BYO mode: private route table IDs. Only needed later, for peering or transit gateway routes."
}
