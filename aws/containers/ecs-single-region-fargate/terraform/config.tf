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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  # set region via $AWS_REGION environment variable
  region = "eu-west-1"

  default_tags {
    tags = {
      managed_by = "Terraform"
    }
  }
}
