################################
# Infra State Data Source     #
################################

data "terraform_remote_state" "infra" {
  backend = "local"

  config = {
    path = var.infra_state_path
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
