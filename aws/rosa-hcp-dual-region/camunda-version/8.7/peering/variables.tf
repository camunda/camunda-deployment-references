variable "cluster_set_name" {
  description = "Name of the cluster set"
  default     = "cl-oc"
  type        = string
}

variable "owner" {
  description = "Information for the owner VPC"
  type = object({
    region                  = string
    vpc_cidr_block          = string
    vpc_id                  = string
    security_group_id       = string
    public_route_table_id   = string
    private_route_table_ids = set(string)
  })
}

variable "accepter" {
  description = "Information for the accepter VPC"
  type = object({
    region                  = string
    vpc_cidr_block          = string
    vpc_id                  = string
    security_group_id       = string
    public_route_table_id   = string
    private_route_table_ids = set(string)
  })
}
