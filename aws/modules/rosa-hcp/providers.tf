data "aws_caller_identity" "current" {}

terraform {
  required_version = ">= 1.0"

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
}
