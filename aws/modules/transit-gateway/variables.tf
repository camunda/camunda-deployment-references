variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "accepter_region" {
  description = "AWS region of the accepter Transit Gateway (used for cross-region peering)"
  type        = string
}
