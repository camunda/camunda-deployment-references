terraform {
  required_version = ">= 1.7.0"
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.74"
    }
  }
}

# Uncomment if used as reference architecture
# If used as module, a provider configuration is not allowed to be defined
provider "aws" {
  # set region via $AWS_REGION environment variable

  default_tags {
    tags = {
      managed_by = "Terraform"
    }
  }
}
