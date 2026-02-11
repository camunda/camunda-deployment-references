terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    rhcs = {
      # TODO: revert to "~> 1.6" once terraform-redhat/rhcs 1.7.3 is republished
      # (v1.7.3 was unpublished: authentication checksums return 404 from github.com)
      version = "~> 1.6, != 1.7.3"
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
