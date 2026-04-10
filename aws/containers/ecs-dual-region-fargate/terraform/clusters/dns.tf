################################################################
#       Route 53 Resolver - Cross-Region DNS Forwarding        #
################################################################
#
# Each region has Cloud Map namespaces for ECS Service Connect.
# Route 53 Resolver endpoints + forwarding rules allow each
# region to resolve the other region's Cloud Map namespace
# over Transit Gateway.
#
# Region 0 forwards queries for r1-*.service.local → Region 1
# Region 1 forwards queries for r0-*.service.local → Region 0

################################
# Region 0 Resolver Endpoints #
################################

resource "aws_route53_resolver_endpoint" "inbound_region_0" {
  name      = "${local.prefix_region_0}-resolver-inbound"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.dns_resolver_region_0.id]

  dynamic "ip_address" {
    for_each = slice(module.vpc_region_0.private_subnets, 0, 2)
    content {
      subnet_id = ip_address.value
    }
  }

  tags = {
    Name = "${local.prefix_region_0}-resolver-inbound"
  }
}

resource "aws_route53_resolver_endpoint" "outbound_region_0" {
  name      = "${local.prefix_region_0}-resolver-outbound"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.dns_resolver_region_0.id]

  dynamic "ip_address" {
    for_each = slice(module.vpc_region_0.private_subnets, 0, 2)
    content {
      subnet_id = ip_address.value
    }
  }

  tags = {
    Name = "${local.prefix_region_0}-resolver-outbound"
  }
}

# Forward queries for region 1 Cloud Map namespace → region 1 inbound resolver
resource "aws_route53_resolver_rule" "region_0_to_region_1" {
  name                 = "${local.prefix_region_0}-fwd-to-r1"
  domain_name          = "${local.prefix_region_1}-oc.service.local"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound_region_0.id

  dynamic "target_ip" {
    for_each = aws_route53_resolver_endpoint.inbound_region_1.ip_address
    content {
      ip = target_ip.value.ip
    }
  }

  tags = {
    Name = "${local.prefix_region_0}-fwd-to-r1"
  }
}

resource "aws_route53_resolver_rule_association" "region_0_to_region_1" {
  resolver_rule_id = aws_route53_resolver_rule.region_0_to_region_1.id
  vpc_id           = module.vpc_region_0.vpc_id
}

################################
# Region 1 Resolver Endpoints #
################################

resource "aws_route53_resolver_endpoint" "inbound_region_1" {
  provider = aws.accepter

  name      = "${local.prefix_region_1}-resolver-inbound"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.dns_resolver_region_1.id]

  dynamic "ip_address" {
    for_each = slice(module.vpc_region_1.private_subnets, 0, 2)
    content {
      subnet_id = ip_address.value
    }
  }

  tags = {
    Name = "${local.prefix_region_1}-resolver-inbound"
  }
}

resource "aws_route53_resolver_endpoint" "outbound_region_1" {
  provider = aws.accepter

  name      = "${local.prefix_region_1}-resolver-outbound"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.dns_resolver_region_1.id]

  dynamic "ip_address" {
    for_each = slice(module.vpc_region_1.private_subnets, 0, 2)
    content {
      subnet_id = ip_address.value
    }
  }

  tags = {
    Name = "${local.prefix_region_1}-resolver-outbound"
  }
}

# Forward queries for region 0 Cloud Map namespace → region 0 inbound resolver
resource "aws_route53_resolver_rule" "region_1_to_region_0" {
  provider = aws.accepter

  name                 = "${local.prefix_region_1}-fwd-to-r0"
  domain_name          = "${local.prefix_region_0}-oc.service.local"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound_region_1.id

  dynamic "target_ip" {
    for_each = aws_route53_resolver_endpoint.inbound_region_0.ip_address
    content {
      ip = target_ip.value.ip
    }
  }

  tags = {
    Name = "${local.prefix_region_1}-fwd-to-r0"
  }
}

resource "aws_route53_resolver_rule_association" "region_1_to_region_0" {
  provider = aws.accepter

  resolver_rule_id = aws_route53_resolver_rule.region_1_to_region_0.id
  vpc_id           = module.vpc_region_1.vpc_id
}
