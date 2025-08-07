terraform {
  required_version = ">= 1.7.0"
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  # set region via $AWS_REGION environment variable
  region = "eu-north-1"

  default_tags {
    tags = {
      managed_by = "Terraform"
    }
  }
}
