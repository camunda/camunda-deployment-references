data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ami" "ami" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (ubuntu)
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-*-server-*"]
  }

  filter {
    name   = "architecture"
    values = [local.aws_instance_architecture]
  }
}

# Output
output "aws_ami" {
  value       = data.aws_ami.ami.id
  description = "The AMI retrieved from AWS for the latest filtered image. Make sure to once pin the aws_ami local variable in ec2.tf to avoid recreations."
}
