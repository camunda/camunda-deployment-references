################################################################################
# Region topology                                                              #
#                                                                              #
# `var.regions` describes the REGION SLOTS of the cluster. The number of slots  #
# is baked into the Zeebe broker identity by the Camunda Helm chart:            #
#                                                                              #
#     nodeId = statefulSetOrdinal * global.multiregion.regions + regionId       #
#                                                                              #
# Changing the number of slots therefore renumbers every broker and is a        #
# destructive operation. Pick the slot count up front, then bring regions       #
# online one at a time with `var.active_region_count`.                          #
#                                                                              #
# See ../../README.md, section "Region slots vs active regions".                #
################################################################################

variable "regions" {
  description = <<-EOT
    Ordered list of region slots. Index 0 is region slot 0, index 1 is region
    slot 1, and so on. The list length is immutable for the lifetime of the
    Camunda cluster because it drives the Zeebe broker node ID stride.

    None of `vpc_cidr_block`, `service_cidr_block` and `pod_cidr_block` may
    overlap, within a region or across regions: Submariner is deployed without
    Globalnet, so every cluster CIDR it learns has to identify exactly one
    cluster, and Transit Gateway cannot route duplicate prefixes either.

    `pod_cidr_block` is attached to the VPC as a SECONDARY CIDR and carries the
    pods only, through VPC CNI custom networking. Keeping pods out of the
    routed node range is what makes Submariner work on EKS; see
    pod-networking.tf and ../../README.md, section "Pod networking".

    `short_name` is used to suffix cluster and resource names and must be a
    valid DNS label.
  EOT

  type = list(object({
    region             = string
    short_name         = string
    vpc_cidr_block     = string
    service_cidr_block = string
    pod_cidr_block     = string
  }))

  default = [
    {
      region             = "eu-west-2" # London
      short_name         = "london"
      vpc_cidr_block     = "10.192.0.0/16" # VPC and node range
      service_cidr_block = "10.190.0.0/16" # Kubernetes service range
      pod_cidr_block     = "100.64.0.0/16" # VPC secondary CIDR, pods only
    },
    {
      region             = "eu-west-3" # Paris
      short_name         = "paris"
      vpc_cidr_block     = "10.202.0.0/16"
      service_cidr_block = "10.200.0.0/16"
      pod_cidr_block     = "100.65.0.0/16"
    },
    {
      region             = "eu-central-2" # Zurich
      short_name         = "zurich"
      vpc_cidr_block     = "10.212.0.0/16"
      service_cidr_block = "10.210.0.0/16"
      pod_cidr_block     = "100.66.0.0/16"
    },
    # Slot 3 is wired but disabled by default. Uncomment to bootstrap a
    # four-region cluster, and raise `replication_factor` in the Helm values
    # accordingly. See ../../README.md.
    # {
    #   region             = "eu-south-1" # Milan
    #   short_name         = "milan"
    #   vpc_cidr_block     = "10.222.0.0/16"
    #   service_cidr_block = "10.220.0.0/16"
    #   pod_cidr_block     = "100.67.0.0/16"
    # },
  ]

  validation {
    condition     = length(var.regions) >= 2 && length(var.regions) <= 4
    error_message = "Between 2 and 4 region slots are supported. Raising the upper bound requires adding provider aliases in config.tf; see README.md."
  }

  validation {
    condition     = length(distinct([for r in var.regions : r.region])) == length(var.regions)
    error_message = "Each region slot must use a distinct AWS region."
  }

  validation {
    condition     = length(distinct([for r in var.regions : r.short_name])) == length(var.regions)
    error_message = "Each region slot must use a distinct short_name; it is used to suffix cluster names."
  }

  validation {
    condition     = length(distinct([for r in var.regions : r.vpc_cidr_block])) == length(var.regions)
    error_message = "Each region slot must use a distinct VPC CIDR block: Submariner runs without Globalnet and Transit Gateway cannot route duplicate prefixes."
  }

  validation {
    condition     = length(distinct([for r in var.regions : r.service_cidr_block])) == length(var.regions)
    error_message = "Each region slot must use a distinct Kubernetes service CIDR block."
  }

  validation {
    condition     = length(distinct([for r in var.regions : r.pod_cidr_block])) == length(var.regions)
    error_message = <<-EOT
      Each region slot must use a distinct pod CIDR block.

      The pod CIDR is never routed between regions, which makes it tempting to
      reuse the same range everywhere. Submariner still refuses it: `subctl
      join` registers the cluster CIDR in the broker and, without Globalnet, a
      prefix that resolves to two clusters cannot be routed into a tunnel. The
      identical constraint is why aws/openshift/rosa-hcp-dual-region uses
      10.0.64.0/18 and 10.1.64.0/18 rather than one range twice.
    EOT
  }

  validation {
    condition = length(distinct(flatten([
      for r in var.regions : [r.vpc_cidr_block, r.service_cidr_block, r.pod_cidr_block]
    ]))) == length(var.regions) * 3
    error_message = "The VPC, service and pod CIDR blocks must all be distinct from each other, within a region and across regions."
  }

  validation {
    condition     = alltrue([for r in var.regions : tonumber(split("/", r.pod_cidr_block)[1]) <= 24])
    error_message = "Each pod CIDR block must be /24 or larger: pod-networking.tf splits it into one subnet per availability zone."
  }
}

variable "active_region_count" {
  description = <<-EOT
    Number of region slots actually deployed. Must be at least
    `length(var.regions) - 1` so that every Zeebe partition keeps a majority of
    its replicas, and at most `length(var.regions)`.

    Deploying fewer regions than slots is the "growth" mode: the cluster runs
    with one replica missing per partition and tolerates no further region
    loss until the remaining regions are activated.
  EOT

  type    = number
  default = 3

  validation {
    condition     = var.active_region_count >= 2
    error_message = "At least two regions must be active."
  }
}

# Cross-validation between the two variables above lives in checks.tf, because
# a variable validation block cannot reference another variable.

################################
# Variables                    #
################################

variable "cluster_name" {
  type        = string
  description = "Name of the cluster to prefix resources. Each region appends its short_name."
}

variable "aws_profile" {
  type        = string
  description = "AWS Profile to use (null = use default credential chain)"
  default     = null
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version to use"
  # renovate: datasource=endoflife-date depName=amazon-eks versioning=loose
  default = "1.36"
}

variable "np_instance_types" {
  type        = list(string)
  description = "Instance types for the node pool"
  default     = ["m6i.xlarge"]
}

variable "np_capacity_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "Allows setting the capacity type to ON_DEMAND or SPOT to determine stable nodes"
}

variable "np_max_node_count" {
  type        = number
  default     = 10
  description = "Maximum number of nodes in the node pool"
}

variable "np_desired_node_count" {
  type        = number
  default     = 4
  description = "Desired number of nodes in the node pool"
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "If true, only one NAT gateway will be created to save on e.g. IPs, not good for HA"
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}

################################
# Derived values               #
################################

locals {
  region_slot_count = length(var.regions)

  # Indices of the regions that are actually deployed.
  active_indices = range(var.active_region_count)

  # CIDRs that must be routable from every region. Kubernetes service CIDRs are
  # included because Submariner Lighthouse resolves ClusterSetIPs out of the
  # service range of the exporting cluster.
  active_vpc_cidr_blocks = [for i in local.active_indices : var.regions[i].vpc_cidr_block]
  active_svc_cidr_blocks = [for i in local.active_indices : var.regions[i].service_cidr_block]
  active_pod_cidr_blocks = [for i in local.active_indices : var.regions[i].pod_cidr_block]

  ##############################################################################
  # Routed CIDRs                                                               #
  #                                                                            #
  # What the Transit Gateway carries between regions. The pod CIDR is          #
  # deliberately ABSENT, and adding it is the single change most likely to     #
  # break this architecture.                                                   #
  #                                                                            #
  # Submariner installs node routes for every remote cluster CIDR it is        #
  # joined with. With the stock VPC CNI the pod range IS the VPC range, so     #
  # those routes also cover the remote NODES — including the gateway endpoints #
  # the tunnels are built on — and cross-region pod traffic never arrives.     #
  # Keeping the pod range out of the routed set, and out of the VPC primary    #
  # CIDR, is what breaks that circularity.                                     #
  #                                                                            #
  # The service CIDR stays: it is a virtual range with no interface in any     #
  # VPC, so a Transit Gateway route for it can never capture a real endpoint.  #
  # It is what Submariner Lighthouse resolves a remote ClusterIP service to.   #
  #                                                                            #
  # See ../../README.md, section "Pod networking".                             #
  ##############################################################################
  region_cidr_blocks = {
    for i in local.active_indices : i => [
      var.regions[i].vpc_cidr_block,
      var.regions[i].service_cidr_block,
    ]
  }

  # CIDRs owned by every region except `i`.
  remote_cidr_blocks = {
    for i in local.active_indices : i => flatten([
      for j in local.active_indices : local.region_cidr_blocks[j] if j != i
    ])
  }

  # Remote CIDRs grouped by the kind of source address a packet can carry, used
  # by security.tf to attach each firewall rule to the addresses that actually
  # originate that traffic.
  #
  #   node — host-network traffic, i.e. the Submariner gateway tunnels
  #   pod  — pod-to-pod traffic, i.e. everything Camunda
  #
  # Service CIDRs are absent on purpose: a ClusterIP is a destination that
  # kube-proxy rewrites at the source node, so it never appears as a source
  # address. They still have to be ROUTED, which is what region_cidr_blocks
  # above is for.
  remote_source_cidr_blocks = {
    for i in local.active_indices : i => {
      node = [for j in local.active_indices : var.regions[j].vpc_cidr_block if j != i]
      pod  = [for j in local.active_indices : var.regions[j].pod_cidr_block if j != i]
    }
  }
}
