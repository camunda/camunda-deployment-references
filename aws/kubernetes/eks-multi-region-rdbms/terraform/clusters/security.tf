################################################################################
# Cross-region firewall rules                                                  #
#                                                                              #
# The dual-region reference architecture opens every protocol between the two   #
# peered VPCs. Here the rules are explicit instead, because the port list is    #
# the most useful piece of documentation for anyone reproducing a Submariner    #
# deployment on EKS, and because the surface grows with every added region.     #
#                                                                              #
# Rules are attached to the EKS-managed primary security group, which is the    #
# security group carried by the managed node group instances AND, through the   #
# ENIConfig objects created by                                                  #
# ../../procedure/configure-vpc-cni-custom-networking.sh, by the pod ENIs of    #
# the custom networking subnets. One security group therefore governs both      #
# host-network traffic (the Submariner tunnels) and pod traffic (Camunda).      #
#                                                                              #
# Every rule declares the KIND of remote address it accepts:                    #
#                                                                              #
#   node — the remote VPC CIDR: Submariner gateways run on the host network,    #
#          so a tunnel packet carries the remote node address                   #
#   pod  — the remote pod CIDR: Submariner preserves source addresses, so a     #
#          cross-region Zeebe packet arrives with the remote POD address        #
#   both — traffic that legitimately originates from either                     #
#                                                                              #
# Splitting the two is not cosmetic. AWS caps a security group at 60 inbound    #
# rules; pairing every rule with every remote CIDR would need 78 for three      #
# regions and 117 for four, and the apply would fail after the clusters and     #
# the database had already been built.                                          #
################################################################################

locals {
  # Submariner data plane. Matches the rule set validated on ROSA in
  # aws/openshift/rosa-hcp-dual-region/terraform/peering/peering.tf, which uses
  # the same libreswan cable driver.
  submariner_rules = [
    {
      key         = "submariner-vxlan"
      scope       = "node"
      from_port   = 4800
      to_port     = 4800
      ip_protocol = "udp"
      description = "Submariner pod traffic encapsulation (VXLAN)"
    },
    {
      key         = "submariner-natt"
      scope       = "node"
      from_port   = 4500
      to_port     = 4500
      ip_protocol = "udp"
      description = "Submariner IPsec NAT traversal encapsulation (NAT-T)"
    },
    {
      key         = "submariner-natt-discovery"
      scope       = "node"
      from_port   = 4490
      to_port     = 4490
      ip_protocol = "udp"
      description = "Submariner NAT traversal discovery"
    },
    {
      key         = "submariner-ike"
      scope       = "node"
      from_port   = 500
      to_port     = 500
      ip_protocol = "udp"
      description = "IPsec IKE negotiation for the Submariner tunnels"
    },
    {
      key   = "submariner-esp"
      scope = "node"
      # Protocol 50 carries no ports, but the provider still expects the pair to
      # be set. -1/-1 is the form already applied in production by
      # aws/openshift/rosa-hcp-dual-region/terraform/peering/peering.tf on the
      # same resource type; null risks a plan or apply error.
      from_port   = -1
      to_port     = -1
      ip_protocol = "50"
      description = "ESP, the encrypted payload of the Submariner IPsec tunnels"
    },
    {
      # The gateway health check pings the remote gateway node, and
      # `subctl diagnose` pings across pods, so both address kinds apply.
      key         = "icmp"
      scope       = "both"
      from_port   = -1
      to_port     = -1
      ip_protocol = "icmp"
      description = "ICMP, used by the Submariner gateway health check and diagnostics"
    },
  ]

  # Camunda Orchestration Cluster. Zeebe brokers form a single Raft cluster
  # stretched across every region, and they address each other pod to pod
  # through the Submariner tunnels, never node to node.
  camunda_rules = [
    {
      key         = "zeebe-gateway-grpc"
      scope       = "pod"
      from_port   = 26500
      to_port     = 26500
      ip_protocol = "tcp"
      description = "Zeebe gateway gRPC API"
    },
    {
      key         = "zeebe-command-api"
      scope       = "pod"
      from_port   = 26501
      to_port     = 26501
      ip_protocol = "tcp"
      description = "Zeebe broker command API"
    },
    {
      key         = "zeebe-internal-api"
      scope       = "pod"
      from_port   = 26502
      to_port     = 26502
      ip_protocol = "tcp"
      description = "Zeebe broker internal API, carries Raft replication across regions"
    },
    {
      # Also carries the Submariner gateway metrics endpoint. AWS deduplicates
      # security group rules by protocol, port range and source, so the two uses
      # share one rule per source kind: a second entry on tcp/8080 from the same
      # CIDR is rejected with InvalidPermission.Duplicate.
      key         = "tcp-8080"
      scope       = "both"
      from_port   = 8080
      to_port     = 8080
      ip_protocol = "tcp"
      description = "Orchestration Cluster v2 REST API and Submariner gateway metrics"
    },
    {
      key         = "orchestration-management"
      scope       = "pod"
      from_port   = 9600
      to_port     = 9600
      ip_protocol = "tcp"
      description = "Orchestration Cluster management API, used by the failover and scaling procedures"
    },
    {
      key         = "kubernetes-dns"
      scope       = "pod"
      from_port   = 53
      to_port     = 53
      ip_protocol = "udp"
      description = "CoreDNS and Submariner Lighthouse DNS resolution"
    },
    {
      key         = "kubernetes-dns-tcp"
      scope       = "pod"
      from_port   = 53
      to_port     = 53
      ip_protocol = "tcp"
      description = "CoreDNS and Submariner Lighthouse DNS resolution over TCP"
    },
  ]

  cross_region_rules = concat(local.submariner_rules, local.camunda_rules)

  # `scope` expanded into one entry per concrete source kind. This is the list
  # the guards in checks.tf work on, because (source kind, protocol, port range)
  # is what AWS actually deduplicates on once the CIDR is filled in.
  cross_region_rule_sources = flatten([
    for rule in local.cross_region_rules : [
      for kind in(rule.scope == "both" ? ["node", "pod"] : [rule.scope]) :
      merge(rule, { source_kind = kind })
    ]
  ])

  # (region slot, remote CIDR, rule) triples, flattened into one map per region
  # so that each aws_vpc_security_group_ingress_rule resource can for_each it.
  #
  # The Terraform key is "<rule>|<cidr>" and deliberately leaves the source kind
  # out: node and pod ranges never overlap, so the CIDR already disambiguates
  # them, and keeping the key stable means a rule that did not change is not
  # destroyed and recreated. That matters here — recreating a rule with the same
  # protocol, port and source risks the create landing before the destroy, which
  # AWS rejects with InvalidPermission.Duplicate.
  ingress_rules_by_region = {
    for i in local.active_indices : i => {
      for entry in flatten([
        for rule in local.cross_region_rule_sources : [
          for cidr in local.remote_source_cidr_blocks[i][rule.source_kind] : {
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
