################################################################
#              Region 0 Security Groups                        #
################################################################

resource "aws_security_group" "camunda_ports_region_0" {
  name        = "${local.prefix_region_0}-camunda-ports"
  description = "Allow necessary Camunda ports within VPC and cross-region"
  vpc_id      = local.vpc.region_0_vpc_id

  # Local VPC Camunda ports
  dynamic "ingress" {
    for_each = var.ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "TCP"
      cidr_blocks = [local.vpc.region_0_vpc_cidr]
      description = "Allow inbound on port ${ingress.value} from local VPC"
    }
  }

  dynamic "egress" {
    for_each = var.ports
    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "TCP"
      cidr_blocks = [local.vpc.region_0_vpc_cidr]
      description = "Allow outbound on port ${egress.value} to local VPC"
    }
  }

  # Cross-region Zeebe cluster traffic from region 1:
  #   26500 gateway gRPC, 26501 broker command API (gateway -> remote partition
  #   leader, broker -> broker), 26502 Raft/cluster
  ingress {
    from_port   = 26500
    to_port     = 26502
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_1_vpc_cidr]
    description = "Allow cross-region Zeebe cluster traffic from region 1"
  }

  egress {
    from_port   = 26500
    to_port     = 26502
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_1_vpc_cidr]
    description = "Allow cross-region Zeebe cluster traffic to region 1"
  }

  # Cross-region Aurora traffic for Aurora Global DB (engine-derived port)
  egress {
    from_port   = local.db_port
    to_port     = local.db_port
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_1_vpc_cidr]
    description = "Allow Aurora traffic to region 1"
  }

  # EFS egress
  egress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "TCP"
    security_groups = [aws_security_group.efs_region_0.id]
    description     = "Allow NFS traffic to EFS"
  }

  tags = {
    Name = "${local.prefix_region_0}-camunda-ports"
  }
}

resource "aws_security_group" "package_80_443_region_0" {
  name        = "${local.prefix_region_0}-package-80-443"
  description = "Allow remote HTTP/HTTPS for package updates"
  vpc_id      = local.vpc.region_0_vpc_id

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound HTTP"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound HTTPS"
  }

  tags = {
    Name = "${local.prefix_region_0}-package-80-443"
  }
}

resource "aws_security_group" "efs_region_0" {
  name        = "${local.prefix_region_0}-efs"
  description = "Security group for EFS"
  vpc_id      = local.vpc.region_0_vpc_id

  ingress {
    description = "NFS from ECS tasks"
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_0_vpc_cidr]
  }

  egress {
    description = "NFS outbound"
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_0_vpc_cidr]
  }

  tags = {
    Name = "${local.prefix_region_0}-efs"
  }
}

resource "aws_security_group" "remote_access_region_0" {
  name        = "${local.prefix_region_0}-remote-access"
  description = "Allow remote access to LoadBalancers"
  vpc_id      = local.vpc.region_0_vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound HTTPS"
  }

  ingress {
    from_port   = 26500
    to_port     = 26500
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound gRPC"
  }

  ingress {
    from_port   = 9600
    to_port     = 9600
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound management"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow outbound to remote CIDRs"
  }

  tags = {
    Name = "${local.prefix_region_0}-remote-access"
  }
}

################################################################
#              Region 1 Security Groups                        #
################################################################

resource "aws_security_group" "camunda_ports_region_1" {
  provider = aws.accepter

  name        = "${local.prefix_region_1}-camunda-ports"
  description = "Allow necessary Camunda ports within VPC and cross-region"
  vpc_id      = local.vpc.region_1_vpc_id

  dynamic "ingress" {
    for_each = var.ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "TCP"
      cidr_blocks = [local.vpc.region_1_vpc_cidr]
      description = "Allow inbound on port ${ingress.value} from local VPC"
    }
  }

  dynamic "egress" {
    for_each = var.ports
    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "TCP"
      cidr_blocks = [local.vpc.region_1_vpc_cidr]
      description = "Allow outbound on port ${egress.value} to local VPC"
    }
  }

  # Cross-region Zeebe cluster traffic from region 0:
  #   26500 gateway gRPC, 26501 broker command API (gateway -> remote partition
  #   leader, broker -> broker), 26502 Raft/cluster
  ingress {
    from_port   = 26500
    to_port     = 26502
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_0_vpc_cidr]
    description = "Allow cross-region Zeebe cluster traffic from region 0"
  }

  egress {
    from_port   = 26500
    to_port     = 26502
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_0_vpc_cidr]
    description = "Allow cross-region Zeebe cluster traffic to region 0"
  }

  # Cross-region Aurora traffic (engine-derived port)
  egress {
    from_port   = local.db_port
    to_port     = local.db_port
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_0_vpc_cidr]
    description = "Allow Aurora traffic to region 0 (Global DB writer)"
  }

  # EFS egress
  egress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "TCP"
    security_groups = [aws_security_group.efs_region_1.id]
    description     = "Allow NFS traffic to EFS"
  }

  tags = {
    Name = "${local.prefix_region_1}-camunda-ports"
  }
}

resource "aws_security_group" "package_80_443_region_1" {
  provider = aws.accepter

  name        = "${local.prefix_region_1}-package-80-443"
  description = "Allow remote HTTP/HTTPS for package updates"
  vpc_id      = local.vpc.region_1_vpc_id

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound HTTP"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound HTTPS"
  }

  tags = {
    Name = "${local.prefix_region_1}-package-80-443"
  }
}

resource "aws_security_group" "efs_region_1" {
  provider = aws.accepter

  name        = "${local.prefix_region_1}-efs"
  description = "Security group for EFS"
  vpc_id      = local.vpc.region_1_vpc_id

  ingress {
    description = "NFS from ECS tasks"
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_1_vpc_cidr]
  }

  egress {
    description = "NFS outbound"
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    cidr_blocks = [local.vpc.region_1_vpc_cidr]
  }

  tags = {
    Name = "${local.prefix_region_1}-efs"
  }
}

resource "aws_security_group" "remote_access_region_1" {
  provider = aws.accepter

  name        = "${local.prefix_region_1}-remote-access"
  description = "Allow remote access to LoadBalancers"
  vpc_id      = local.vpc.region_1_vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound HTTPS"
  }

  ingress {
    from_port   = 26500
    to_port     = 26500
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound gRPC"
  }

  ingress {
    from_port   = 9600
    to_port     = 9600
    protocol    = "tcp"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow inbound management"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.limit_access_to_cidrs
    description = "Allow outbound to remote CIDRs"
  }

  tags = {
    Name = "${local.prefix_region_1}-remote-access"
  }
}
