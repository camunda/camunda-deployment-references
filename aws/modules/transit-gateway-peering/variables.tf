variable "name" {
  description = "Name prefix for the peering attachment, typically `<cluster_name>-<owner_short_name>-<accepter_short_name>`"
  type        = string
}

variable "owner_transit_gateway_id" {
  description = "ID of the Transit Gateway initiating the peering request"
  type        = string
}

variable "owner_transit_gateway_route_table_id" {
  description = "Route table ID of the owner Transit Gateway, where routes to the accepter CIDRs are installed"
  type        = string
}

variable "owner_cidr_blocks" {
  description = "CIDR blocks reachable through the owner Transit Gateway"
  type        = list(string)
}

variable "accepter_transit_gateway_id" {
  description = "ID of the Transit Gateway accepting the peering request"
  type        = string
}

variable "accepter_transit_gateway_route_table_id" {
  description = "Route table ID of the accepter Transit Gateway, where routes to the owner CIDRs are installed"
  type        = string
}

variable "accepter_cidr_blocks" {
  description = "CIDR blocks reachable through the accepter Transit Gateway"
  type        = list(string)
}
