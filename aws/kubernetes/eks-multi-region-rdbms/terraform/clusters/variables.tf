################################################################################
# Region topology                                                              #
#                                                                              #
# `var.regions` describes the REGION SLOTS of the cluster. The number of slots  #
# is baked into the Zeebe broker identity by the Camunda Helm chart:            #
#                                                                              #
#     nodeId = statefulSetOrdinal * orchestration.multiregion.regions + regionId       #
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

    `vpc_cidr_block` and `service_cidr_block` must not overlap across regions:
    Transit Gateway cannot route duplicate prefixes, and Submariner runs
    without Globalnet so every CIDR it learns has to identify exactly one
    cluster.

    There is no separate pod range. With the AWS VPC CNI a pod address IS a VPC
    address, so pods are reachable across regions over the Transit Gateway with
    no overlay; see ../../README.md, section "Cross-region networking".

    `short_name` is used to suffix cluster and resource names and must be a
    valid DNS label.
  EOT

  type = list(object({
    region             = string
    short_name         = string
    vpc_cidr_block     = string
    service_cidr_block = string
  }))

  default = [
    {
      region             = "eu-west-2" # London
      short_name         = "london"
      vpc_cidr_block     = "10.192.0.0/16" # VPC, node and pod range
      service_cidr_block = "10.190.0.0/16" # Kubernetes service range
    },
    {
      region             = "eu-west-3" # Paris
      short_name         = "paris"
      vpc_cidr_block     = "10.202.0.0/16"
      service_cidr_block = "10.200.0.0/16"
    },
    {
      region             = "eu-central-2" # Zurich
      short_name         = "zurich"
      vpc_cidr_block     = "10.212.0.0/16"
      service_cidr_block = "10.210.0.0/16"
    },
    # Slot 3 is wired but disabled by default. Uncomment to bootstrap a
    # four-region cluster, and raise `replication_factor` in the Helm values
    # accordingly. See ../../README.md.
    # {
    #   region             = "eu-south-1" # Milan
    #   short_name         = "milan"
    #   vpc_cidr_block     = "10.222.0.0/16"
    #   service_cidr_block = "10.220.0.0/16"
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

  # One pool, not two. Checking the VPC blocks against each other and the service
  # blocks against each other leaves a VPC block free to collide with another
  # slot's service block, which is the same duplicate prefix: Submariner runs
  # without Globalnet and Transit Gateway cannot route one.
  validation {
    condition = length(distinct(concat(
      [for r in var.regions : r.vpc_cidr_block],
      [for r in var.regions : r.service_cidr_block],
    ))) == 2 * length(var.regions)
    error_message = "Every VPC and Kubernetes service CIDR block must be distinct across all region slots, service blocks included: Submariner runs without Globalnet and Transit Gateway cannot route duplicate prefixes."
  }

  # Distinct is not enough: 10.0.0.0/16 and 10.0.128.0/17 are different strings
  # that describe overlapping address space, which routes just as badly and fails
  # later and less legibly, somewhere inside Submariner.
  #
  # Terraform has no overlap function. Two prefixes overlap exactly when they
  # have the same network address once both are masked to the shorter of the two
  # prefix lengths, and `cidrhost(addr/p, 0)` is that masking. Pairs where both
  # sides are the same string are skipped; the validation above already rejects
  # those, and here they would report every block as overlapping itself.
  validation {
    condition = alltrue([
      for pair in setproduct(
        concat([for r in var.regions : r.vpc_cidr_block], [for r in var.regions : r.service_cidr_block]),
        concat([for r in var.regions : r.vpc_cidr_block], [for r in var.regions : r.service_cidr_block]),
      ) :
      pair[0] == pair[1] || (
        cidrhost("${split("/", pair[0])[0]}/${min(tonumber(split("/", pair[0])[1]), tonumber(split("/", pair[1])[1]))}", 0)
        !=
        cidrhost("${split("/", pair[1])[0]}/${min(tonumber(split("/", pair[0])[1]), tonumber(split("/", pair[1])[1]))}", 0)
      )
    ])
    error_message = "No VPC or Kubernetes service CIDR block may overlap another, across all region slots and across both kinds: Submariner runs without Globalnet and cannot disambiguate overlapping address space."
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

  ##############################################################################
  # Routed CIDRs                                                               #
  #                                                                            #
  # What the Transit Gateway carries between regions, and everything that has  #
  # to reach another region.                                                   #
  #                                                                            #
  # The VPC CIDR covers the pods as well as the nodes: with the AWS VPC CNI a  #
  # pod address is an ordinary VPC address, so routing the VPC range is what   #
  # makes cross-region pod-to-pod traffic work, natively and with no overlay.  #
  # The service CIDR is included because Submariner Lighthouse resolves a      #
  # remote ClusterIP service out of the exporting cluster's service range.     #
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
}
