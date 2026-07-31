################################
# Backend & Provider Setup    #
################################

terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

################################################################################
# Provider slots                                                               #
#                                                                              #
# Terraform cannot generate provider configurations dynamically, so one alias   #
# per region SLOT is declared statically. `local.region_slot_count` is derived  #
# from `var.regions`; slots beyond that length fall back to region 0 and are    #
# never used because every resource attached to them is count-gated to zero.    #
#                                                                              #
# Raising MAX_REGION_SLOTS is a mechanical change: add a provider block here,   #
# a cluster module in clusters.tf, a Transit Gateway hub in                     #
# transit-gateway.tf and the new peering pairs. See README.md.                  #
#                                                                              #
# Every provider block validates its credentials with sts:GetCallerIdentity at  #
# plan time, including the slots that create nothing. Four blocks per plan,     #
# times the workflows this repository runs in parallel, is enough to trip STS   #
# request-rate limits:                                                          #
#                                                                              #
#   Error: validating provider credentials: retrieving caller identity from     #
#   STS: operation error STS: GetCallerIdentity, exceeded maximum number of     #
#   attempts                                                                    #
#                                                                              #
# `retry_mode = "adaptive"` adds the SDK's client-side rate limiter, which      #
# backs off on throttling instead of retrying at a fixed cadence, and the       #
# attempt budget is raised from the default. Credential validation is           #
# deliberately NOT skipped: it is the fastest signal that the CI credentials    #
# are wrong, and losing it would trade a clear early failure for an obscure     #
# later one.                                                                    #
################################################################################

locals {
  # Applied to every provider block below.
  aws_retry_mode  = "adaptive"
  aws_max_retries = 10
}

provider "aws" {
  region  = var.regions[0].region
  profile = var.aws_profile # optional, feel free to remove if you use the default profile

  retry_mode  = local.aws_retry_mode
  max_retries = local.aws_max_retries

  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  alias   = "region_1"
  region  = try(var.regions[1].region, var.regions[0].region)
  profile = var.aws_profile

  retry_mode  = local.aws_retry_mode
  max_retries = local.aws_max_retries

  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  alias   = "region_2"
  region  = try(var.regions[2].region, var.regions[0].region)
  profile = var.aws_profile

  retry_mode  = local.aws_retry_mode
  max_retries = local.aws_max_retries

  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  alias   = "region_3"
  region  = try(var.regions[3].region, var.regions[0].region)
  profile = var.aws_profile

  retry_mode  = local.aws_retry_mode
  max_retries = local.aws_max_retries

  default_tags {
    tags = var.default_tags
  }
}
