################################################################
#       Route 53 Resolver Security Groups                       #
#                                                                #
# Only created when enable_cross_region_dns_resolver = true.    #
# Allows DNS (TCP/UDP 53) between the two VPCs over peering/TGW.#
################################################################

resource "aws_security_group" "dns_resolver_region_0" {
  count = var.enable_cross_region_dns_resolver ? 1 : 0

  name        = "${local.prefix_region_0}-dns-resolver"
  description = "Security group for Route 53 Resolver endpoints"
  vpc_id      = local.region_0_vpc_id

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [local.region_0_vpc_cidr, local.region_1_vpc_cidr]
    description = "DNS TCP from both VPCs"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [local.region_0_vpc_cidr, local.region_1_vpc_cidr]
    description = "DNS UDP from both VPCs"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [local.region_0_vpc_cidr, local.region_1_vpc_cidr]
    description = "DNS TCP to both VPCs"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [local.region_0_vpc_cidr, local.region_1_vpc_cidr]
    description = "DNS UDP to both VPCs"
  }

  tags = {
    Name = "${local.prefix_region_0}-dns-resolver"
  }
}

resource "aws_security_group" "dns_resolver_region_1" {
  count    = var.enable_cross_region_dns_resolver ? 1 : 0
  provider = aws.accepter

  name        = "${local.prefix_region_1}-dns-resolver"
  description = "Security group for Route 53 Resolver endpoints"
  vpc_id      = local.region_1_vpc_id

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [local.region_0_vpc_cidr, local.region_1_vpc_cidr]
    description = "DNS TCP from both VPCs"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [local.region_0_vpc_cidr, local.region_1_vpc_cidr]
    description = "DNS UDP from both VPCs"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [local.region_0_vpc_cidr, local.region_1_vpc_cidr]
    description = "DNS TCP to both VPCs"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [local.region_0_vpc_cidr, local.region_1_vpc_cidr]
    description = "DNS UDP to both VPCs"
  }

  tags = {
    Name = "${local.prefix_region_1}-dns-resolver"
  }
}
