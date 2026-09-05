################################################################################
# Cross-region firewall rules                                                  #
#                                                                              #
# The dual-region reference architecture opens every protocol between the two   #
# peered VPCs. Here the rules are explicit instead, because the port list is    #
# the most useful piece of documentation for anyone reproducing this            #
# architecture, and because the surface grows with every added region.          #
#                                                                              #
# Rules are attached to the EKS-managed primary security group, which is the    #
# security group carried by the managed node group instances and therefore by  #
# the pods: with the AWS VPC CNI a pod address is a VPC address on a node       #
# interface, so one security group governs both.                               #
#                                                                              #
# There are no Submariner tunnel ports here. Submariner is deployed for service #
# discovery only; the data plane is the Transit Gateway, so there is no IPsec   #
# or VXLAN to authorise. See ../../README.md, "Cross-region networking".        #
################################################################################

locals {
  # Camunda Orchestration Cluster. Zeebe brokers form a single Raft cluster
  # stretched across every region, so these must be reachable region to region.
  cross_region_rules = [
    {
      # One range rather than three rules: AWS keys a security group rule by
      # protocol, port range and source, so a range is a single rule and leaves
      # room under the 60-rule limit as regions are added.
      key         = "zeebe-apis"
      from_port   = 26500
      to_port     = 26502
      ip_protocol = "tcp"
      description = "Zeebe gateway gRPC, broker command API, and the internal API carrying Raft replication"
    },
    {
      key         = "orchestration-rest"
      from_port   = 8080
      to_port     = 8080
      ip_protocol = "tcp"
      description = "Orchestration Cluster v2 REST API"
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
      description = "ICMP, used by the cross-region connectivity diagnostics"
    },
  ]

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
