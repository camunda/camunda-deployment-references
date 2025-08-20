locals {
  generate_ssh_key_pair = false               # Generate an SSH key pair for the EC2 instances over the use of pub_key_path. Meant for testing purposes / temp environments.
  pub_key_path          = "~/.ssh/id_rsa.pub" # Path to the public key to use for the EC2 instances for SSH access. If generate_ssh_key_pair is true, this will be ignored.
  limit_access_to_cidrs = ["0.0.0.0/0"]       # List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer. If you want to limit access, set this to your IP range.
  ports = {
    ssh                                   = 22
    opensearch_https                      = 443
    camunda_web_ui                        = 8080
    camunda_metrics_endpoint              = 9600
    connectors_port                       = 9090
    zeebe_gateway_cluster_port            = 26502
    zeebe_gateway_network_port            = 26500
    zeebe_broker_network_command_api_port = 26501
  }
}

resource "aws_kms_key" "main" {
  description             = "${var.prefix} - KMS key for encrypting EBS volumes and OpenSearch"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "tls_private_key" "testing" {
  count = local.generate_ssh_key_pair ? 1 : 0

  algorithm = "ED25519"
}

resource "aws_key_pair" "main" {
  key_name   = "${var.prefix}-auth-key"
  public_key = local.generate_ssh_key_pair ? tls_private_key.testing[0].public_key_openssh : file(local.pub_key_path)
}

resource "aws_security_group" "allow_necessary_camunda_ports_within_vpc" {
  name        = "allow_necessary_camunda_ports_within_vpc"
  description = "Allow necessary Camunda ports within the VPC"
  vpc_id      = module.vpc.vpc_id

  dynamic "ingress" {
    for_each = local.ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "TCP"
      cidr_blocks = [module.vpc.vpc_cidr_block]
      description = "Allow inbound traffic on port ${ingress.value}"
    }
  }

  dynamic "egress" {
    for_each = local.ports
    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "TCP"
      cidr_blocks = [module.vpc.vpc_cidr_block]
      description = "Allow outbound traffic on port ${egress.value}"
    }
  }

  tags = {
    Name = "allow_necessary_camunda_ports_within_vpc"
  }
}

resource "aws_security_group" "allow_package_80_443" {
  name        = "allow_package_80_443"
  description = "Allow remote HTTP and HTTPS traffic for e.g. package updates"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound HTTP traffic"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound HTTPS traffic"
  }

  tags = {
    Name = "allow_package_80_443"
  }
}

resource "aws_security_group" "allow_remote_80_443" {
  name        = "allow_remote_80_443"
  description = "Allow remote HTTP and HTTPS traffic for LoadBalancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.limit_access_to_cidrs
    description = "Allow inbound HTTP traffic"
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.limit_access_to_cidrs
    description = "Allow outbound HTTP traffic"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.limit_access_to_cidrs
    description = "Allow inbound HTTPS traffic"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.limit_access_to_cidrs
    description = "Allow outbound HTTPS traffic"
  }

  tags = {
    Name = "allow_remote_80_443"
  }
}

resource "aws_security_group" "allow_remote_9090" {
  name        = "allow_remote_9090"
  description = "Allow remote traffic on 9090 for the LoadBalancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = local.limit_access_to_cidrs
    description = "Allow inbound traffic on port 9090"
  }

  egress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = local.limit_access_to_cidrs
    description = "Allow outbound traffic on port 9090"
  }

  tags = {
    Name = "allow_remote_9090"
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.limit_access_to_cidrs
    description = "Allow inbound SSH traffic"
  }

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_security_group" "allow_remote_grpc" {
  name        = "allow_remote_grpc"
  description = "Allow remote gRPC traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 26500
    to_port     = 26500
    protocol    = "tcp"
    cidr_blocks = local.limit_access_to_cidrs
    description = "Allow inbound gRPC traffic on port 26500"
  }

  tags = {
    Name = "allow_remote_grpc"
  }
}

# Outputs
output "private_key" {
  value       = join("", tls_private_key.testing[*].private_key_openssh)
  sensitive   = true
  description = "(Optional) This private key is meant for testing purposes only and enabled via the variable `generate_ssh_key_pair`."
}

output "public_key" {
  value       = join("", tls_private_key.testing[*].public_key_openssh)
  sensitive   = true
  description = "(Optional) This public key is meant for testing purposes only and enabled via the variable `generate_ssh_key_pair`. Please supply your own public key via the variable `pub_key_path`."
}
