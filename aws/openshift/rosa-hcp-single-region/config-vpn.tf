# Provider configuration file used only for the VPN
# It configures the region used by the bucket storing certificates

provider "aws" {
  region = var.s3_bucket_region
  alias  = "aws_bucket_provider"
}

variable "s3_bucket_region" {
  type        = string
  description = "Region of the bucket"
  default     = "eu-central-1"
}
