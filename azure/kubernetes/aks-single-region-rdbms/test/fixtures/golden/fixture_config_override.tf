# This file is used for automated tests only, and should be removed for Azure deployments
terraform {
  required_version = ">= 1.0"

  backend "s3" {
    encrypt = true
  }
}
