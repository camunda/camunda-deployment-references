################################
# Backend & Provider Setup    #
################################

terraform {
  # 1.9 rather than 1.6: the db_iam_auth_enabled and db_seed_iam_usernames
  # validations reference other input variables (secondary_storage_type,
  # db_engine), which input-variable validation only supports from Terraform
  # 1.9. On 1.6-1.8 the configuration fails to load rather than failing a
  # check, so the floor has to say so.
  required_version = ">= 1.9.0"

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
