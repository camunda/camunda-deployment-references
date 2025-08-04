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

# Two provider configurations are needed to create resources in two different regions
provider "aws" {
  region = var.cluster_1_region
  alias  = "cluster_1"
  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  region = var.cluster_2_region
  alias  = "cluster_2"
  default_tags {
    tags = var.default_tags
  }
}

#### Variables

variable "cluster_1_region" {
  description = "Region of the cluster 1"
  default     = "us-east-1"
  type        = string
}

variable "cluster_2_region" {
  description = "Region of the cluster 2"
  default     = "us-east-2"
  type        = string
}
variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}
