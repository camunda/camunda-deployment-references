terraform {
  # 1.1 rather than 1.0: the engine version pins use nullable = false, which
  # was added for input variables in Terraform 1.1.
  required_version = ">= 1.1"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.primary, aws.secondary]
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
