terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.69" # Adjust version as needed
    }
  }

  backend "s3" {
    encrypt = true
  }

  required_version = ">= 1.3.0" # Adjust Terraform version as needed
}

provider "aws" {}
