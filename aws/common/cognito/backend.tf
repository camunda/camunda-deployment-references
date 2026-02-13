# This file declares an S3 backend for storing Terraform state.
# Backend configuration values are passed via `-backend-config` during `terraform init`.
#
# Example:
#   terraform init \
#     -backend-config="bucket=your-state-bucket" \
#     -backend-config="key=cognito-test/your-cluster/terraform.tfstate" \  # NOTE: S3 key prefix kept as cognito-test/ for backward compatibility
#     -backend-config="region=eu-central-1"

terraform {
  backend "s3" {}
}
