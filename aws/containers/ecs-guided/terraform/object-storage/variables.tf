variable "prefix" {
  type        = string
  description = "Name prefix of the buckets"
}

variable "aws_region" {
  type        = string
  description = "Region of the buckets"
}

variable "zones" {
  type        = set(string)
  description = "Names of the zones of the Orchestration Cluster. One node ID lease bucket is created per zone: a lease bucket is never shared between zones or clusters."

  validation {
    condition     = length(var.zones) >= 1 && alltrue([for z in var.zones : can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,62}$", z))])
    error_message = "zones needs at least one name made of alphanumerics and hyphens, starting with an alphanumeric."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Delete the buckets even if they contain objects. Dev and test only."
}
