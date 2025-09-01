################################
# Backend & Provider Setup    #
################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    encrypt = true
  }
}

# For ease of the configuration, a third provider is used only for the bucket creation
provider "aws" {
  region = var.backup_bucket_region

  default_tags {
    tags = var.default_tags
  }
}

#### Variables

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}
variable "backup_bucket_region" {
  description = "Region of the backup bucket"
  default     = "us-east-1"
  type        = string
}
