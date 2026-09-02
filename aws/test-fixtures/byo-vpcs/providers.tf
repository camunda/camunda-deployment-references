provider "aws" {
  alias   = "region_0"
  region  = var.region_0
  profile = var.aws_profile
  default_tags { tags = var.tags }
}

provider "aws" {
  alias   = "region_1"
  region  = var.region_1
  profile = var.aws_profile
  default_tags { tags = var.tags }
}
