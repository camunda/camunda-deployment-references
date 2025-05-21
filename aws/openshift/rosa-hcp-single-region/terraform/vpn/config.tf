# Provider configuration file used only for the VPN
# It configures the region used by the bucket storing certificates
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.35.0"
    }
  }

  backend "s3" {
    encrypt = true
  }
}
provider "aws" {
  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  region = var.s3_bucket_region
  alias  = "aws_bucket_provider"
  default_tags {
    tags = var.default_tags
  }
}

#### Variables

variable "s3_bucket_region" {
  type        = string
  description = "Region of the bucket"
  default     = "eu-central-1"
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}
