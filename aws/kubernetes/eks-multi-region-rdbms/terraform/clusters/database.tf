################################################################################
# Secondary storage: Aurora Global Database                                    #
#                                                                              #
# Camunda 8.10 exposes exactly ONE JDBC connection per Orchestration Cluster    #
# when RDBMS secondary storage is used, and the RDBMS exporter has no           #
# multi-region mode. Replication is therefore delegated entirely to the         #
# database, which is what makes this reference architecture replication         #
# agnostic: Camunda only ever sees a single URL.                                #
#                                                                              #
# Aurora Global Database is the implementation exercised here, but any backend  #
# exposing a single writer endpoint that survives a region loss works the same  #
# way (Patroni + a floating endpoint, CockroachDB, AlloyDB, a managed proxy...). #
# Set `deploy_database = false` and feed `CAMUNDA_RDBMS_URL` yourself to use     #
# one.                                                                          #
#                                                                              #
# Note that the database regions are deliberately decoupled from the compute    #
# regions: `database_region_slots` selects which region slots host a database   #
# member. A three-region Zeebe cluster backed by a two-region Aurora Global      #
# database is a valid and cheaper topology.                                     #
################################################################################

variable "deploy_database" {
  type        = bool
  default     = true
  description = "Whether to create the Aurora Global Database. Set to false to bring your own RDBMS."
}

variable "database_region_slots" {
  type        = list(number)
  default     = [0, 1]
  description = <<-EOT
    Region slots that host an Aurora Global Database member. Must be a subset of
    the active region slots and must contain slot 0.

    Slot 0 is always the writer. That is not a limitation of Aurora, which can
    promote any member, but of Terraform: the secondary members have to wait for
    the writer to exist before they can attach to the global cluster, and that
    ordering has to reference a statically known module. Pinning the writer to
    slot 0 keeps the dependency correct by construction. A failover still moves
    the writer wherever you want at runtime; see procedure/failover.sh.

    Defaults to two regions: Aurora Global Database is not available in every
    AWS region, and the Zeebe topology does not require a database member in
    each region. Brokers in regions without a member reach the writer over the
    Transit Gateway mesh.
  EOT

  validation {
    condition     = length(var.database_region_slots) >= 1 && length(var.database_region_slots) <= 4
    error_message = "Between 1 and 4 database region slots are supported."
  }

  validation {
    condition     = length(distinct(var.database_region_slots)) == length(var.database_region_slots)
    error_message = "database_region_slots must not contain duplicates."
  }

  validation {
    condition     = alltrue([for slot in var.database_region_slots : slot >= 0 && slot == floor(slot)])
    error_message = "database_region_slots must contain non-negative integer slot numbers."
  }

  validation {
    condition     = contains(var.database_region_slots, 0)
    error_message = "database_region_slots must contain slot 0: it hosts the Aurora Global Database writer."
  }
}

variable "database_name" {
  type        = string
  default     = "camunda"
  description = "Name of the database backing the Camunda secondary storage"
}

variable "database_username" {
  type        = string
  default     = "camunda"
  description = "Master username of the Aurora Global Database"
  sensitive   = true
}

variable "database_engine_version" {
  type = string
  # renovate: datasource=custom.aurora-pg-camunda depName=aurora-postgresql versioning=loose
  default     = "17.9"
  description = "Aurora PostgreSQL engine version. Camunda 8.10 supports PostgreSQL 15 to 18."
}

variable "database_instance_class" {
  type        = string
  default     = "db.r6g.large"
  description = "Instance class of the Aurora cluster instances"
}

variable "database_instances_per_region" {
  type        = number
  default     = 1
  description = "Number of Aurora instances per region. Use at least 2 in production for intra-region failover."
}

variable "database_iam_auth_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether IAM database authentication is enabled on the Aurora clusters.

    Kept off by default: the reference deployment authenticates with a password
    stored in a Kubernetes secret, which is the portable path that works with
    any RDBMS. Turning it on additionally requires IRSA roles carrying
    rds-db:connect for every regional cluster; see
    aws/kubernetes/eks-single-region-irsa for the IRSA pattern.
  EOT
}

check "database_region_slots_are_active" {
  assert {
    condition     = alltrue([for slot in var.database_region_slots : slot < var.active_region_count])
    error_message = "database_region_slots must only reference region slots that are active (active_region_count = ${var.active_region_count})."
  }
}

################################
# Credentials                  #
################################

resource "random_password" "database" {
  count = var.deploy_database ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#%&*()-_=+[]{}:?"
}

################################
# Global cluster               #
################################

resource "aws_rds_global_cluster" "camunda" {
  count = var.deploy_database ? 1 : 0

  global_cluster_identifier = "${var.cluster_name}-global-db"
  engine                    = "aurora-postgresql"
  engine_version            = var.database_engine_version
  database_name             = var.database_name
  storage_encrypted         = true
}

locals {
  database_enabled = var.deploy_database

  # Every CIDR that must be able to reach the database. The VPC range covers the
  # pods as well as the nodes, and brokers in regions without a local member
  # connect to the writer across the Transit Gateway.
  database_allowed_cidr_blocks = concat(local.active_vpc_cidr_blocks, local.active_svc_cidr_blocks)

  # Always slot 0; see the database_region_slots validation above.
  database_writer_slot = 0

  database_member_enabled = {
    for i in range(4) : i => local.database_enabled && contains(var.database_region_slots, i)
  }
}

################################################################################
# Regional members                                                             #
#                                                                              #
# `is_primary` marks the writer. Secondary members must be created after the    #
# primary is available, otherwise AWS creates them standalone and refuses to    #
# attach them to the global cluster afterwards.                                 #
################################################################################

module "database_region_0" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/aurora-global-member"

  count = local.database_member_enabled[0] ? 1 : 0

  cluster_identifier        = "${var.cluster_name}-${var.regions[0].short_name}-db"
  global_cluster_identifier = one(aws_rds_global_cluster.camunda[*].id)
  is_primary                = true

  engine_version = var.database_engine_version
  instance_class = var.database_instance_class
  num_instances  = var.database_instances_per_region

  database_name      = var.database_name
  master_username    = var.database_username
  master_password    = one(random_password.database[*].result)
  availability_zones = local.clusters[0].vpc_azs

  vpc_id              = local.clusters[0].vpc_id
  subnet_ids          = local.clusters[0].private_subnet_ids
  allowed_cidr_blocks = local.database_allowed_cidr_blocks
  iam_auth_enabled    = var.database_iam_auth_enabled
}

# Secondary members wait for the writer to settle before attaching: AWS creates
# them standalone otherwise, and then refuses to attach an existing standalone
# cluster to a global cluster. The writer is slot 0 by construction, so this
# dependency is always the right one.
resource "time_sleep" "wait_for_database_writer" {
  count = local.database_enabled ? 1 : 0

  depends_on      = [module.database_region_0]
  create_duration = "30s"
}

module "database_region_1" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/aurora-global-member"

  count = local.database_member_enabled[1] ? 1 : 0

  cluster_identifier        = "${var.cluster_name}-${var.regions[1].short_name}-db"
  global_cluster_identifier = one(aws_rds_global_cluster.camunda[*].id)
  # Secondary member: master credentials, database name and availability zones
  # are inherited from the writer through replication and rejected by AWS here.
  is_primary = false

  engine_version = var.database_engine_version
  instance_class = var.database_instance_class
  num_instances  = var.database_instances_per_region

  vpc_id              = local.clusters[1].vpc_id
  subnet_ids          = local.clusters[1].private_subnet_ids
  allowed_cidr_blocks = local.database_allowed_cidr_blocks
  iam_auth_enabled    = var.database_iam_auth_enabled

  providers = {
    aws = aws.region_1
  }

  depends_on = [time_sleep.wait_for_database_writer]
}

module "database_region_2" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/aurora-global-member"

  count = local.database_member_enabled[2] ? 1 : 0

  cluster_identifier        = "${var.cluster_name}-${var.regions[2].short_name}-db"
  global_cluster_identifier = one(aws_rds_global_cluster.camunda[*].id)
  # Secondary member: master credentials, database name and availability zones
  # are inherited from the writer through replication and rejected by AWS here.
  is_primary = false

  engine_version = var.database_engine_version
  instance_class = var.database_instance_class
  num_instances  = var.database_instances_per_region

  vpc_id              = local.clusters[2].vpc_id
  subnet_ids          = local.clusters[2].private_subnet_ids
  allowed_cidr_blocks = local.database_allowed_cidr_blocks
  iam_auth_enabled    = var.database_iam_auth_enabled

  providers = {
    aws = aws.region_2
  }

  depends_on = [time_sleep.wait_for_database_writer]
}

module "database_region_3" {
  # tflint-ignore: terraform_module_pinned_source
  source = "../../../../modules/aurora-global-member"

  count = local.database_member_enabled[3] ? 1 : 0

  cluster_identifier        = "${var.cluster_name}-${var.regions[3].short_name}-db"
  global_cluster_identifier = one(aws_rds_global_cluster.camunda[*].id)
  # Secondary member: master credentials, database name and availability zones
  # are inherited from the writer through replication and rejected by AWS here.
  is_primary = false

  engine_version = var.database_engine_version
  instance_class = var.database_instance_class
  num_instances  = var.database_instances_per_region

  vpc_id              = local.clusters[3].vpc_id
  subnet_ids          = local.clusters[3].private_subnet_ids
  allowed_cidr_blocks = local.database_allowed_cidr_blocks
  iam_auth_enabled    = var.database_iam_auth_enabled

  providers = {
    aws = aws.region_3
  }

  depends_on = [time_sleep.wait_for_database_writer]
}

locals {
  database_members = {
    for i, m in [
      module.database_region_0,
      module.database_region_1,
      module.database_region_2,
      module.database_region_3,
    ] : i => one(m) if length(m) > 0
  }

  # Instance host patterns for the AWS Advanced JDBC Wrapper. Passing every
  # member lets the driver discover the new writer after a global failover
  # without any change to the Camunda configuration.
  database_host_patterns = join(",", [for m in values(local.database_members) : m.instance_host_pattern])

  database_writer_endpoint = try(local.database_members[local.database_writer_slot].endpoint, null)
}
