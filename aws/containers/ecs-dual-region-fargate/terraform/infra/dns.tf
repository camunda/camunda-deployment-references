################################################################
#       Route 53 Resolver - Cross-Region DNS Forwarding        #
################################################################
#
# Each region has Cloud Map namespaces for ECS Service Connect.
# Route 53 Resolver endpoints + forwarding rules allow each
# region to resolve the other region's Cloud Map namespace
# over VPC Peering.
#
# Region 0 forwards queries for r1-*.service.local → Region 1
# Region 1 forwards queries for r0-*.service.local → Region 0
#
# NOTE: Creating resolver endpoints requires the IAM permission
#   route53resolver:CreateResolverEndpoint on the calling principal.
#   If your SSO/IAM role lacks this permission, set
#   enable_cross_region_dns_resolver = false (the default).
#   Zeebe Raft and Connectors still work without it because cross-region
#   contact uses NLB DNS names, not Service Connect names.

################################
# Region 0 Resolver Endpoints #
################################

resource "aws_route53_resolver_endpoint" "inbound_region_0" {
  count = var.enable_cross_region_dns_resolver ? 1 : 0

  name      = "${local.prefix_region_0}-resolver-inbound"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.dns_resolver_region_0.id]

  dynamic "ip_address" {
    for_each = module.vpc_region_0.private_subnets
    content {
      subnet_id = ip_address.value
    }
  }

  tags = {
    Name = "${local.prefix_region_0}-resolver-inbound"
  }
}

resource "aws_route53_resolver_endpoint" "outbound_region_0" {
  count = var.enable_cross_region_dns_resolver ? 1 : 0

  name      = "${local.prefix_region_0}-resolver-outbound"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.dns_resolver_region_0.id]

  dynamic "ip_address" {
    for_each = module.vpc_region_0.private_subnets
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
  count = var.enable_cross_region_dns_resolver ? 1 : 0

  name                 = "${local.prefix_region_0}-fwd-to-r1"
  domain_name          = "${local.prefix_region_1}-oc.service.local"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound_region_0[0].id

  dynamic "target_ip" {
    for_each = aws_route53_resolver_endpoint.inbound_region_1[0].ip_address
    content {
      ip = target_ip.value.ip
    }
  }

  tags = {
    Name = "${local.prefix_region_0}-fwd-to-r1"
  }
}

resource "aws_route53_resolver_rule_association" "region_0_to_region_1" {
  count = var.enable_cross_region_dns_resolver ? 1 : 0

  resolver_rule_id = aws_route53_resolver_rule.region_0_to_region_1[0].id
  vpc_id           = module.vpc_region_0.vpc_id
}

################################
# Region 1 Resolver Endpoints #
################################

resource "aws_route53_resolver_endpoint" "inbound_region_1" {
  count    = var.enable_cross_region_dns_resolver ? 1 : 0
  provider = aws.accepter

  name      = "${local.prefix_region_1}-resolver-inbound"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.dns_resolver_region_1.id]

  dynamic "ip_address" {
    for_each = module.vpc_region_1.private_subnets
    content {
      subnet_id = ip_address.value
    }
  }

  tags = {
    Name = "${local.prefix_region_1}-resolver-inbound"
  }
}

resource "aws_route53_resolver_endpoint" "outbound_region_1" {
  count    = var.enable_cross_region_dns_resolver ? 1 : 0
  provider = aws.accepter

  name      = "${local.prefix_region_1}-resolver-outbound"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.dns_resolver_region_1.id]

  dynamic "ip_address" {
    for_each = module.vpc_region_1.private_subnets
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
  count    = var.enable_cross_region_dns_resolver ? 1 : 0
  provider = aws.accepter

  name                 = "${local.prefix_region_1}-fwd-to-r0"
  domain_name          = "${local.prefix_region_0}-oc.service.local"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound_region_1[0].id

  dynamic "target_ip" {
    for_each = aws_route53_resolver_endpoint.inbound_region_0[0].ip_address
    content {
      ip = target_ip.value.ip
    }
  }

  tags = {
    Name = "${local.prefix_region_1}-fwd-to-r0"
  }
}

resource "aws_route53_resolver_rule_association" "region_1_to_region_0" {
  count    = var.enable_cross_region_dns_resolver ? 1 : 0
  provider = aws.accepter

  resolver_rule_id = aws_route53_resolver_rule.region_1_to_region_0[0].id
  vpc_id           = module.vpc_region_1.vpc_id
}
