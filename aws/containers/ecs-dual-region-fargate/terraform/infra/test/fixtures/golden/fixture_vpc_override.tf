# Golden-plan fixture (Terraform override file, copied into the module root by
# the `regenerate-golden-file` recipe and removed afterwards).
#
# The infra/ state cannot be planned standalone because it:
#   1. reads the sibling vpc/ state via data.terraform_remote_state.vpc over an
#      S3 backend that does not exist during golden generation, and
#   2. performs live data.aws_subnet lookups on the subnet IDs from that state
#      (to derive the private-subnet AZs for Aurora).
#
# Here we disable both reads (count = 0) and inject a static, deterministic
# snapshot of the vpc outputs (local.vpc) and the derived AZ lists
# (region_{0,1}_azs). Everything else — KMS keys, IAM, Aurora Global, ALB/NLB,
# security groups, secrets — is planned for real, which is the drift we want the
# golden file to catch. data.aws_caller_identity stays live; the account ID it
# yields appears only inside ARNs, which the recipe redacts.
#
# Values are placeholders; subnet/VPC IDs are syntactically valid but fake.

data "terraform_remote_state" "vpc" {
  count = 0
}

data "aws_subnet" "region_0_private" {
  count = 0
}

data "aws_subnet" "region_1_private" {
  count = 0
}

locals {
  vpc = {
    region_0_vpc_id             = "vpc-00000000000000000"
    region_0_vpc_cidr           = "10.192.0.0/16"
    region_0_private_subnet_ids = ["subnet-000000000000000a0", "subnet-000000000000000b0", "subnet-000000000000000c0"]
    region_0_public_subnet_ids  = ["subnet-000000000000000d0", "subnet-000000000000000e0", "subnet-000000000000000f0"]

    region_1_vpc_id             = "vpc-11111111111111111"
    region_1_vpc_cidr           = "10.202.0.0/16"
    region_1_private_subnet_ids = ["subnet-000000000000000a1", "subnet-000000000000000b1", "subnet-000000000000000c1"]
    region_1_public_subnet_ids  = ["subnet-000000000000000d1", "subnet-000000000000000e1", "subnet-000000000000000f1"]
  }

  # data.aws_subnet.region_{0,1}_private are disabled with count = 0 above because
  # the fake subnet IDs cannot be looked up live. Their only consumer today is the
  # region_*_azs locals, so we re-inject region_0_azs directly (aurora-global.tf reads
  # it as primary_availability_zones). region_1_azs is intentionally NOT set: the module
  # defines it but no resource consumes it. If a future change consumes these data sources
  # in a new way (e.g. region_1_azs for the secondary cluster, or subnet CIDRs), add the
  # corresponding static value here — otherwise it resolves to empty only in the golden plan.
  region_0_azs = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
}
