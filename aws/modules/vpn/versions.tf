terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.35.0"
    }

    # TODO: this triggers a warning, check with Lars how to fix that
    aws-bucket = {
      source  = "hashicorp/aws"
      version = ">= 5.35.0"
    }
  }
}
