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
################################################################################

provider "aws" {
  region  = var.regions[0].region
  profile = var.aws_profile # optional, feel free to remove if you use the default profile
  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  alias   = "region_1"
  region  = try(var.regions[1].region, var.regions[0].region)
  profile = var.aws_profile
  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  alias   = "region_2"
  region  = try(var.regions[2].region, var.regions[0].region)
  profile = var.aws_profile
  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  alias   = "region_3"
  region  = try(var.regions[3].region, var.regions[0].region)
  profile = var.aws_profile
  default_tags {
    tags = var.default_tags
  }
}
