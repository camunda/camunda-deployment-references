################################################################
#          Infra Layer State Reference                          #
################################################################
# Reads outputs from the infra layer so this layer can reference
# VPC IDs, ECS cluster IDs, LB ARNs, IAM role ARNs, etc. without
# duplicating or hard-coding them.
#
# For a local state backend (the default), run:
#   cd ../infra && terraform init && terraform apply
# before applying this layer.
#
# For a remote backend (S3, Terraform Cloud, etc.) replace the
# backend type and config block below accordingly.

data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = var.infra_state_path
  }
}
