variable "prefix" {
  type        = string
  description = "Prefix for test resource names (typically the test's RunID)"
}

variable "aws_profile" {
  type        = string
  default     = null
  description = "AWS profile (null = default credential chain)"
}

variable "region_0" {
  type        = string
  default     = "eu-west-2"
  description = "Region 0 for the byo VPC fixture"
}

variable "region_1" {
  type        = string
  default     = "eu-west-3"
  description = "Region 1 for the byo VPC fixture"
}

variable "region_0_cidr" {
  type    = string
  default = "10.150.0.0/16"
}

variable "region_1_cidr" {
  type    = string
  default = "10.160.0.0/16"
}

variable "tags" {
  type    = map(string)
  default = {}
}
