# this file is used to declare a backend used during the tests

terraform {
  backend "s3" {}
}

provider "aws" {
  default_tags {
    tags = var.default_tags
  }

  # cloud-nuke adds this tag to fresh resources and breaks the idempotency check
  ignore_tags {
    keys = ["cloud-nuke-first-seen"]
  }
}

#### Variables

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}
