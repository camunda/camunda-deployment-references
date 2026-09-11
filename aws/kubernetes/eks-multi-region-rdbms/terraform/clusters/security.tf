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
# or VXLAN to authorise.                                                        #
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

  ingress_rules = {
    for entry in flatten([
      for i in local.active_indices : [
        for cidr in local.remote_cidr_blocks[i] : [
          for rule in local.cross_region_rules : {
            key         = "${i}|${rule.key}|${cidr}"
            region_slot = i
            cidr        = cidr
            from_port   = rule.from_port
            to_port     = rule.to_port
            ip_protocol = rule.ip_protocol
            description = rule.description
          }
        ]
      ]
    ]) : entry.key => entry
  }
}

resource "aws_vpc_security_group_ingress_rule" "cross_region" {
  for_each = local.ingress_rules

  region            = var.regions[each.value.region_slot].region
  security_group_id = local.clusters[each.value.region_slot].cluster_primary_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.ip_protocol
  description       = each.value.description
}
