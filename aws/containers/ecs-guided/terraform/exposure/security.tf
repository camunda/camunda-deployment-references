resource "aws_security_group" "remote_grpc" {
  name        = "${var.prefix}-allow-remote-grpc"
  description = "Allow remote gRPC traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 26500
    to_port     = 26500
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound gRPC traffic on port 26500"
  }
}

resource "aws_security_group" "remote_9600" {
  name        = "${var.prefix}-allow-remote-9600"
  description = "Allow remote traffic on 9600 for the load balancer"
  vpc_id      = var.vpc_id

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
}

resource "aws_security_group" "remote_80_443" {
  name        = "${var.prefix}-allow-remote-80-443"
  description = "Allow remote HTTP and HTTPS traffic for the load balancer"
  vpc_id      = var.vpc_id

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
}
