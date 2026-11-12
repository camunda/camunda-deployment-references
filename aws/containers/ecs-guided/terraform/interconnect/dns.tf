# Each region has a private service discovery namespace. Resolver endpoints and forwarding
# rules let a name registered in one region resolve in the other, over the peering link.
#
#   region A resolves <domain B> through region B's inbound endpoint, and the other way round.

locals {
  both_cidrs = [var.vpc_cidr_a, var.vpc_cidr_b]
}

resource "aws_security_group" "resolver_a" {
  count = var.enable_dns_resolver ? 1 : 0

  region      = var.region_a
  name        = "${var.prefix}-a-dns-resolver"
  description = "Route 53 Resolver endpoints"
  vpc_id      = var.vpc_id_a

  dynamic "ingress" {
    for_each = ["tcp", "udp"]
    content {
      from_port   = 53
      to_port     = 53
      protocol    = ingress.value
      cidr_blocks = local.both_cidrs
      description = "DNS ${ingress.value} from both VPCs"
    }
  }

  dynamic "egress" {
    for_each = ["tcp", "udp"]
    content {
      from_port   = 53
      to_port     = 53
      protocol    = egress.value
      cidr_blocks = local.both_cidrs
      description = "DNS ${egress.value} to both VPCs"
    }
  }
}

resource "aws_security_group" "resolver_b" {
  count = var.enable_dns_resolver ? 1 : 0

  region      = var.region_b
  name        = "${var.prefix}-b-dns-resolver"
  description = "Route 53 Resolver endpoints"
  vpc_id      = var.vpc_id_b

  dynamic "ingress" {
    for_each = ["tcp", "udp"]
    content {
      from_port   = 53
      to_port     = 53
      protocol    = ingress.value
      cidr_blocks = local.both_cidrs
      description = "DNS ${ingress.value} from both VPCs"
    }
  }

  dynamic "egress" {
    for_each = ["tcp", "udp"]
    content {
      from_port   = 53
      to_port     = 53
      protocol    = egress.value
      cidr_blocks = local.both_cidrs
      description = "DNS ${egress.value} to both VPCs"
    }
  }
}

resource "aws_route53_resolver_endpoint" "inbound_a" {
  count = var.enable_dns_resolver ? 1 : 0

  region             = var.region_a
  name               = "${var.prefix}-a-resolver-inbound"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.resolver_a[0].id]

  dynamic "ip_address" {
    for_each = slice(var.private_subnet_ids_a, 0, 2)
    content {
      subnet_id = ip_address.value
    }
  }
}

resource "aws_route53_resolver_endpoint" "outbound_a" {
  count = var.enable_dns_resolver ? 1 : 0

  region             = var.region_a
  name               = "${var.prefix}-a-resolver-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.resolver_a[0].id]

  dynamic "ip_address" {
    for_each = slice(var.private_subnet_ids_a, 0, 2)
    content {
      subnet_id = ip_address.value
    }
  }
}

resource "aws_route53_resolver_endpoint" "inbound_b" {
  count = var.enable_dns_resolver ? 1 : 0

  region             = var.region_b
  name               = "${var.prefix}-b-resolver-inbound"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.resolver_b[0].id]

  dynamic "ip_address" {
    for_each = slice(var.private_subnet_ids_b, 0, 2)
    content {
      subnet_id = ip_address.value
    }
  }
}

resource "aws_route53_resolver_endpoint" "outbound_b" {
  count = var.enable_dns_resolver ? 1 : 0

  region             = var.region_b
  name               = "${var.prefix}-b-resolver-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.resolver_b[0].id]

  dynamic "ip_address" {
    for_each = slice(var.private_subnet_ids_b, 0, 2)
    content {
      subnet_id = ip_address.value
    }
  }
}

# Region A forwards the domain of region B to region B's inbound endpoint.
resource "aws_route53_resolver_rule" "a_to_b" {
  count = var.enable_dns_resolver ? 1 : 0

  region               = var.region_a
  name                 = "${var.prefix}-a-forwards-to-b"
  domain_name          = var.service_discovery_domain_b
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound_a[0].id

  dynamic "target_ip" {
    for_each = aws_route53_resolver_endpoint.inbound_b[0].ip_address
    content {
      ip = target_ip.value.ip
    }
  }
}

resource "aws_route53_resolver_rule_association" "a_to_b" {
  count = var.enable_dns_resolver ? 1 : 0

  region           = var.region_a
  resolver_rule_id = aws_route53_resolver_rule.a_to_b[0].id
  vpc_id           = var.vpc_id_a
}

resource "aws_route53_resolver_rule" "b_to_a" {
  count = var.enable_dns_resolver ? 1 : 0

  region               = var.region_b
  name                 = "${var.prefix}-b-forwards-to-a"
  domain_name          = var.service_discovery_domain_a
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound_b[0].id

  dynamic "target_ip" {
    for_each = aws_route53_resolver_endpoint.inbound_a[0].ip_address
    content {
      ip = target_ip.value.ip
    }
  }
}

resource "aws_route53_resolver_rule_association" "b_to_a" {
  count = var.enable_dns_resolver ? 1 : 0

  region           = var.region_b
  resolver_rule_id = aws_route53_resolver_rule.b_to_a[0].id
  vpc_id           = var.vpc_id_b
}
