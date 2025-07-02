data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"] # Debian
  filter {
    name   = "name"
    values = ["debian-12-*"]
  }

  filter {
    name   = "architecture"
    values = [local.aws_instance_architecture]
  }
}

# Output
output "aws_ami" {
  value       = data.aws_ami.debian.id
  description = "The AMI retrieved from AWS for the latest Debian 12 image. Make sure to once pin the aws_ami variable to avoid recreations."
}
