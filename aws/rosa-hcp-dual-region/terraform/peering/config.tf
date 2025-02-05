################################
# Backend & Provider Setup    #
################################

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

# Two provider configurations are needed to create resources in two different regions
provider "aws" {
  region = var.cluster_1_region
  alias  = "cluster_1"
}

provider "aws" {
  region = var.cluster_2_region
  alias  = "cluster_2"
}
