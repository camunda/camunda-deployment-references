################################
# Infra State Data Source     #
################################

data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.terraform_backend_bucket
    key    = "${var.terraform_backend_key_prefix}infra/terraform.tfstate"
    region = var.terraform_backend_region
  }
}

# Convenience local to avoid repeating data.terraform_remote_state.infra.outputs everywhere
locals {
  infra = data.terraform_remote_state.infra.outputs
}

# Data sources needed by modules
data "aws_region" "region_0" {}

data "aws_region" "region_1" {
  provider = aws.accepter
}
