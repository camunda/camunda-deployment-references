terraform {
  required_version = ">= 1.7.0"

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
  region = var.region_a

  default_tags {
    tags = var.default_tags
  }
}
