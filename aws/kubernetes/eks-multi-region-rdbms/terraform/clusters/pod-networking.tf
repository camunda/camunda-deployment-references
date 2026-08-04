################################################################################
# Pod networking: VPC CNI custom networking                                    #
#                                                                              #
# By default the AWS VPC CNI hands pods addresses out of the node subnets, so   #
# pod IPs ARE VPC IPs. That is what makes the single-region and dual-region EKS #
# references simple, and it is exactly what breaks here.                        #
#                                                                              #
# Submariner installs node routes for every remote cluster CIDR it is joined    #
# with, so that packets addressed to a remote pod enter its tunnel. When the    #
# pod range is the VPC range, those routes also cover the remote NODES —        #
# including the gateway addresses the tunnels are themselves built on. The      #
# Transit Gateway meanwhile still advertises the same prefix. Peers resolve,    #
# poll requests time out, and the Zeebe brokers never form a Raft quorum.       #
#                                                                              #
# The fix is to separate the two ranges, which is the situation OVNKubernetes   #
# gives for free on ROSA and which the dual-region OpenShift reference relies    #
# on:                                                                           #
#                                                                              #
#   nodes -> var.regions[i].vpc_cidr_block   routed over the Transit Gateway    #
#   pods  -> var.regions[i].pod_cidr_block   routed by Submariner only          #
#                                                                              #
# The pod range is attached as a VPC SECONDARY CIDR out of 100.64.0.0/10        #
# (RFC 6598 shared address space). It sits outside the RFC 1918 plan, so it      #
# cannot collide with a corporate network being peered in later, and AWS        #
# documents it as the range to use for custom networking.                       #
#                                                                              #
# Terraform providers cannot be iterated, so each region slot is written out    #
# explicitly and gated on `count`, exactly like clusters.tf.                    #
#                                                                              #
# The Kubernetes side (the aws-node DaemonSet flags and the ENIConfig objects)  #
# lives in ../../procedure/configure-vpc-cni-custom-networking.sh: it has to    #
# run against a cluster that already exists, and this reference architecture     #
# keeps day-1 Kubernetes configuration in procedures rather than in a           #
# Kubernetes provider, so that a reader can follow it by hand.                   #
################################################################################

locals {
  # One pod subnet per availability zone. `newbits = 2` addresses up to four
  # zones, which is the ceiling asserted in checks.tf. A fixed split is used
  # instead of one derived from the zone count so that the subnet layout does
  # not shift — and every pod address with it — when a zone is added.
  pod_subnet_newbits = 2

  pod_subnet_tags = {
    # Conventional marker for subnets that only carry CNI ENIs. Deliberately
    # NOT tagged kubernetes.io/role/internal-elb: load balancers must keep
    # landing in the routed node subnets.
    "kubernetes.io/role/cni" = "1"
  }
}

################################
# Region slot 0                #
################################

resource "aws_vpc_ipv4_cidr_block_association" "pods_region_0" {
  count = var.active_region_count > 0 ? 1 : 0

  vpc_id     = local.clusters[0].vpc_id
  cidr_block = var.regions[0].pod_cidr_block
}

resource "aws_subnet" "pods_region_0" {
  count = var.active_region_count > 0 ? length(local.clusters[0].vpc_azs) : 0

  vpc_id            = local.clusters[0].vpc_id
  availability_zone = local.clusters[0].vpc_azs[count.index]
  cidr_block        = cidrsubnet(var.regions[0].pod_cidr_block, local.pod_subnet_newbits, count.index)

  tags = merge(local.pod_subnet_tags, {
    Name = "${var.cluster_name}-${var.regions[0].short_name}-pods-${local.clusters[0].vpc_azs[count.index]}"
  })

  # The subnet cannot be carved out of a CIDR the VPC does not carry yet.
  depends_on = [aws_vpc_ipv4_cidr_block_association.pods_region_0]
}

# Pods still need egress (image pulls, the AWS APIs, the Camunda registry), so
# the pod subnets share the private route tables and therefore the NAT gateways
# of the node subnets. `element` wraps the list, which covers both the
# one-route-table-per-zone layout and the single_nat_gateway layout used in CI.
resource "aws_route_table_association" "pods_region_0" {
  count = var.active_region_count > 0 ? length(local.clusters[0].vpc_azs) : 0

  subnet_id      = aws_subnet.pods_region_0[count.index].id
  route_table_id = element(local.clusters[0].private_route_table_ids, count.index)
}

################################
# Region slot 1                #
################################

resource "aws_vpc_ipv4_cidr_block_association" "pods_region_1" {
  provider = aws.region_1

  count = var.active_region_count > 1 ? 1 : 0

  vpc_id     = local.clusters[1].vpc_id
  cidr_block = var.regions[1].pod_cidr_block
}

resource "aws_subnet" "pods_region_1" {
  provider = aws.region_1

  count = var.active_region_count > 1 ? length(local.clusters[1].vpc_azs) : 0

  vpc_id            = local.clusters[1].vpc_id
  availability_zone = local.clusters[1].vpc_azs[count.index]
  cidr_block        = cidrsubnet(var.regions[1].pod_cidr_block, local.pod_subnet_newbits, count.index)

  tags = merge(local.pod_subnet_tags, {
    Name = "${var.cluster_name}-${var.regions[1].short_name}-pods-${local.clusters[1].vpc_azs[count.index]}"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.pods_region_1]
}

resource "aws_route_table_association" "pods_region_1" {
  provider = aws.region_1

  count = var.active_region_count > 1 ? length(local.clusters[1].vpc_azs) : 0

  subnet_id      = aws_subnet.pods_region_1[count.index].id
  route_table_id = element(local.clusters[1].private_route_table_ids, count.index)
}

################################
# Region slot 2                #
################################

resource "aws_vpc_ipv4_cidr_block_association" "pods_region_2" {
  provider = aws.region_2

  count = var.active_region_count > 2 ? 1 : 0

  vpc_id     = local.clusters[2].vpc_id
  cidr_block = var.regions[2].pod_cidr_block
}

resource "aws_subnet" "pods_region_2" {
  provider = aws.region_2

  count = var.active_region_count > 2 ? length(local.clusters[2].vpc_azs) : 0

  vpc_id            = local.clusters[2].vpc_id
  availability_zone = local.clusters[2].vpc_azs[count.index]
  cidr_block        = cidrsubnet(var.regions[2].pod_cidr_block, local.pod_subnet_newbits, count.index)

  tags = merge(local.pod_subnet_tags, {
    Name = "${var.cluster_name}-${var.regions[2].short_name}-pods-${local.clusters[2].vpc_azs[count.index]}"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.pods_region_2]
}

resource "aws_route_table_association" "pods_region_2" {
  provider = aws.region_2

  count = var.active_region_count > 2 ? length(local.clusters[2].vpc_azs) : 0

  subnet_id      = aws_subnet.pods_region_2[count.index].id
  route_table_id = element(local.clusters[2].private_route_table_ids, count.index)
}

################################
# Region slot 3                #
################################

resource "aws_vpc_ipv4_cidr_block_association" "pods_region_3" {
  provider = aws.region_3

  count = var.active_region_count > 3 ? 1 : 0

  vpc_id     = local.clusters[3].vpc_id
  cidr_block = var.regions[3].pod_cidr_block
}

resource "aws_subnet" "pods_region_3" {
  provider = aws.region_3

  count = var.active_region_count > 3 ? length(local.clusters[3].vpc_azs) : 0

  vpc_id            = local.clusters[3].vpc_id
  availability_zone = local.clusters[3].vpc_azs[count.index]
  cidr_block        = cidrsubnet(var.regions[3].pod_cidr_block, local.pod_subnet_newbits, count.index)

  tags = merge(local.pod_subnet_tags, {
    Name = "${var.cluster_name}-${var.regions[3].short_name}-pods-${local.clusters[3].vpc_azs[count.index]}"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.pods_region_3]
}

resource "aws_route_table_association" "pods_region_3" {
  provider = aws.region_3

  count = var.active_region_count > 3 ? length(local.clusters[3].vpc_azs) : 0

  subnet_id      = aws_subnet.pods_region_3[count.index].id
  route_table_id = element(local.clusters[3].private_route_table_ids, count.index)
}

locals {
  # Uniform view over the count-gated pod subnets, so the outputs do not repeat
  # the ternaries above.
  pod_subnet_ids = {
    for i, subnets in [
      aws_subnet.pods_region_0,
      aws_subnet.pods_region_1,
      aws_subnet.pods_region_2,
      aws_subnet.pods_region_3,
    ] : i => subnets[*].id if length(subnets) > 0
  }
}
