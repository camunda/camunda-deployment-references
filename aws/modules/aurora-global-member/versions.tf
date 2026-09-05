terraform {
  # 1.2 for `precondition`, which main.tf uses to reject a primary member
  # declared without its credentials or zones.
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
