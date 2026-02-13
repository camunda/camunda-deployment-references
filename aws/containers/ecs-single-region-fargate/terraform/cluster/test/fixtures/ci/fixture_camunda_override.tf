# we are enabling force destroy for CI testing purposes
# using an override allows to not have to expose it at all to users
# overrides just adds this argument to the module call

module "orchestration_cluster" {
  s3_force_destroy = true
}

resource "aws_s3_bucket" "backup" {
  force_destroy = true
}
