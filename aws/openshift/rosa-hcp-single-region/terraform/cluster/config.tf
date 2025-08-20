terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    rhcs = {
      version = "~> 1.6"
      source  = "terraform-redhat/rhcs"
    }
  }

  backend "s3" {
    encrypt = true
  }
}

# ensure  RHCS_TOKEN env variable is set with a value from https://console.redhat.com/openshift/token/rosa
provider "rhcs" {}

provider "aws" {
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
