# tflint-ignore-file: all

# This file is used to override the provider configuration for CI purposes
# We can't use a provider block upstream as it would block module usage
provider "aws" {
  # configuration is done via the AWS CLI

  default_tags {
    tags = {
      managed_by = "Terraform"
    }
  }
}
