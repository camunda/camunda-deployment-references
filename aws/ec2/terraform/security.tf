locals {
  // 2650x - Zeebe
  // 9600 - Metrics endpoint
  // 9090 - Connectors
  // 8080 - Camunda WebUi
  // 443 - HTTPS (e.g. OpenSearch)
  vpc_ports = [26500, 26501, 26502, 9600, 9090, 8080, 443]
}

resource "aws_kms_key" "main" {
  description             = "${var.prefix} - KMS key for encrypting EBS volumes and OpenSearch"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "tls_private_key" "testing" {
  count = var.generate_ssh_key_pair ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = "${var.prefix}-auth-key"
  public_key = var.generate_ssh_key_pair ? tls_private_key.testing[0].public_key_openssh : file(var.pub_key_path)
}

resource "aws_security_group" "allow_necessary_camunda_ports_within_vpc" {
  name        = "allow_necessary_camunda_ports_within_vpc"
  description = "Allow necessary Camunda ports within the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  dynamic "ingress" {
    for_each = local.vpc_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "TCP"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }

  }

  dynamic "egress" {
    for_each = local.vpc_ports

    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "TCP"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  tags = {
    Name = "allow_necessary_camunda_ports_within_vpc"
  }
}

resource "aws_security_group" "allow_remote_80_443" {
  name        = "allow_remote_80_443"
  description = "Allow remote HTTP and HTTPS traffic for e.g. package updates"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_remote_80_443"
  }
}

resource "aws_security_group" "allow_remote_9090" {
  name        = "allow_remote_9090"
  description = "Allow remote traffic on 9090 for the LB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_remote_grpc"
  }
}
