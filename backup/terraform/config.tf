terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.97"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "eu-north-1"
}
