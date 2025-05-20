terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.35.0"
    }
  }
}

provider "aws" {
  alias = "aws_region_vpn"
}

provider "aws" {
  region = var.s3_bucket_region
  alias  = "aws_region_bucket"
}
