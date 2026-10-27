data "aws_caller_identity" "current" {}

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    rhcs = {
      # 1.7.11 was published without the provider binary.
      version = "~> 1.6, != 1.7.11"
      source  = "terraform-redhat/rhcs"
    }
  }
}
