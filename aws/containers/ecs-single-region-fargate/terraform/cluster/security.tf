
resource "aws_security_group" "allow_necessary_camunda_ports_within_vpc" {
  name        = "${var.prefix}-allow-necessary-camunda-ports-within-vpc"
  description = "Allow necessary Camunda ports within the VPC"
  vpc_id      = module.vpc.vpc_id

  dynamic "ingress" {
    for_each = var.ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "TCP"
      cidr_blocks = [module.vpc.vpc_cidr_block]
      description = "Allow inbound traffic on port ${ingress.value}"
    }
  }

  dynamic "egress" {
    for_each = var.ports
    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "TCP"
      cidr_blocks = [module.vpc.vpc_cidr_block]
      description = "Allow outbound traffic on port ${egress.value}"
    }
  }

  # Allow NFS traffic to EFS
  egress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "TCP"
    security_groups = [aws_security_group.efs.id]
    description     = "Allow NFS traffic to EFS"
  }

  tags = {
    Name = "allow_necessary_camunda_ports_within_vpc"
  }
}

resource "aws_security_group" "allow_package_80_443" {
  name        = "${var.prefix}-allow-package-80-443"
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

resource "aws_security_group" "efs" {
  name        = "${var.prefix}-efs"
  description = "Security group for EFS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "nfs from ECS tasks"
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    description = "nfs outbound"
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  tags = {
    Name = "${var.prefix}-efs"
  }
}

################################################################
#                 Remote Access                                #
################################################################

resource "aws_security_group" "allow_remote_grpc" {
  name        = "allow_remote_grpc"
  description = "Allow remote gRPC traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 26500
    to_port     = 26500
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound gRPC traffic on port 26500"
  }

  tags = {
    Name = "allow_remote_grpc"
  }
}

resource "aws_security_group" "allow_remote_9600" {
  name        = "allow_remote_9600"
  description = "Allow remote traffic on 9600 for the LoadBalancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 9600
    to_port     = 9600
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound traffic on port 9600"
  }

  egress {
    from_port   = 9600
    to_port     = 9600
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow outbound traffic on port 9600"
  }

  tags = {
    Name = "allow_remote_9600"
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
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound HTTP traffic"
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow outbound HTTP traffic"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound HTTPS traffic"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow outbound HTTPS traffic"
  }

  tags = {
    Name = "allow_remote_80_443"
  }
}
