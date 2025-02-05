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

    rhcs = {
      version = "1.6.8"
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
}

provider "aws" {
  region = var.cluster_2_region
  alias  = "cluster_2"
}
