################################################################################
# Cross-region firewall rules                                                  #
#                                                                              #
# The dual-region reference architecture opens every protocol between the two   #
# peered VPCs. Here the rules are explicit instead, because the port list is    #
# the most useful piece of documentation for anyone reproducing a Submariner    #
# deployment on EKS, and because the surface grows with every added region.     #
#                                                                              #
# Rules are attached to the EKS-managed primary security group, which is the    #
# security group carried by the managed node group instances. Submariner runs   #
# on the host network of the gateway nodes, so node-level rules are what        #
# matters for the IPsec tunnels.                                                #
################################################################################

locals {
  # Submariner data plane. Matches the rule set validated on ROSA in
  # aws/openshift/rosa-hcp-dual-region/terraform/peering/peering.tf, which uses
  # the same libreswan cable driver.
  submariner_rules = [
    {
      key         = "submariner-vxlan"
      from_port   = 4800
      to_port     = 4800
      ip_protocol = "udp"
      description = "Submariner pod traffic encapsulation (VXLAN)"
    },
    {
      key         = "submariner-natt"
      from_port   = 4500
      to_port     = 4500
      ip_protocol = "udp"
      description = "Submariner IPsec NAT traversal encapsulation (NAT-T)"
    },
    {
      key         = "submariner-natt-discovery"
      from_port   = 4490
      to_port     = 4490
      ip_protocol = "udp"
      description = "Submariner NAT traversal discovery"
    },
    {
      key         = "submariner-ike"
      from_port   = 500
      to_port     = 500
      ip_protocol = "udp"
      description = "IPsec IKE negotiation for the Submariner tunnels"
    },
    {
      key = "submariner-esp"
      # Protocol 50 carries no ports, but the provider still expects the pair to
      # be set. -1/-1 is the form already applied in production by
      # aws/openshift/rosa-hcp-dual-region/terraform/peering/peering.tf on the
      # same resource type; null risks a plan or apply error.
      from_port   = -1
      to_port     = -1
      ip_protocol = "50"
      description = "ESP, the encrypted payload of the Submariner IPsec tunnels"
    },
  ]

  # Camunda Orchestration Cluster. Zeebe brokers form a single Raft cluster
  # stretched across every region, so these must be reachable region to region.
  camunda_rules = [
    {
      key         = "zeebe-gateway-grpc"
      from_port   = 26500
      to_port     = 26500
      ip_protocol = "tcp"
      description = "Zeebe gateway gRPC API"
    },
    {
      key         = "zeebe-command-api"
      from_port   = 26501
      to_port     = 26501
      ip_protocol = "tcp"
      description = "Zeebe broker command API"
    },
    {
      key         = "zeebe-internal-api"
      from_port   = 26502
      to_port     = 26502
      ip_protocol = "tcp"
      description = "Zeebe broker internal API, carries Raft replication across regions"
    },
    {
      # Also carries the Submariner gateway metrics and health endpoint. AWS
      # deduplicates security group rules by protocol and port range, so the
      # two uses must share one rule: a second entry on tcp/8080 from the same
      # CIDR is rejected with InvalidPermission.Duplicate.
      key         = "tcp-8080"
      from_port   = 8080
      to_port     = 8080
      ip_protocol = "tcp"
      description = "Orchestration Cluster v2 REST API and Submariner gateway metrics"
    },
    {
      key         = "orchestration-management"
      from_port   = 9600
      to_port     = 9600
      ip_protocol = "tcp"
      description = "Orchestration Cluster management API, used by the failover and scaling procedures"
    },
    {
      key         = "kubernetes-dns"
      from_port   = 53
      to_port     = 53
      ip_protocol = "udp"
      description = "CoreDNS and Submariner Lighthouse DNS resolution"
    },
    {
      key         = "kubernetes-dns-tcp"
      from_port   = 53
      to_port     = 53
      ip_protocol = "tcp"
      description = "CoreDNS and Submariner Lighthouse DNS resolution over TCP"
    },
    {
      key         = "icmp"
      from_port   = -1
      to_port     = -1
      ip_protocol = "icmp"
      description = "ICMP, required by the Submariner connectivity diagnostics"
    },
  ]

  cross_region_rules = concat(local.submariner_rules, local.camunda_rules)

  # (region slot, remote CIDR, rule) triples, flattened into one map per region
  # so that each aws_vpc_security_group_ingress_rule resource can for_each it.
  ingress_rules_by_region = {
    for i in local.active_indices : i => {
      for entry in flatten([
        for cidr in local.remote_cidr_blocks[i] : [
          for rule in local.cross_region_rules : {
            key         = "${rule.key}|${cidr}"
            cidr        = cidr
            from_port   = rule.from_port
            to_port     = rule.to_port
            ip_protocol = rule.ip_protocol
            description = rule.description
          }
        ]
      ]) : entry.key => entry
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "region_0" {
  for_each = var.active_region_count > 0 ? local.ingress_rules_by_region[0] : {}

  security_group_id = local.clusters[0].cluster_primary_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.ip_protocol
  description       = each.value.description
}

resource "aws_vpc_security_group_ingress_rule" "region_1" {
  provider = aws.region_1

  for_each = var.active_region_count > 1 ? local.ingress_rules_by_region[1] : {}

  security_group_id = local.clusters[1].cluster_primary_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.ip_protocol
  description       = each.value.description
}

resource "aws_vpc_security_group_ingress_rule" "region_2" {
  provider = aws.region_2

  for_each = var.active_region_count > 2 ? local.ingress_rules_by_region[2] : {}

  security_group_id = local.clusters[2].cluster_primary_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.ip_protocol
  description       = each.value.description
}

resource "aws_vpc_security_group_ingress_rule" "region_3" {
  provider = aws.region_3

  for_each = var.active_region_count > 3 ? local.ingress_rules_by_region[3] : {}

  security_group_id = local.clusters[3].cluster_primary_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.ip_protocol
  description       = each.value.description
}
