################################
# Backend & Provider Setup    #
################################

terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.region_0
  profile = var.aws_profile
  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  region  = var.region_1
  alias   = "accepter"
  profile = var.aws_profile
  default_tags {
    tags = var.default_tags
  }
}
