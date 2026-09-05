###############################################################################
# One regional member of an Aurora Global Database                            #
#                                                                             #
# This module deliberately owns a SINGLE region so that an N-region topology   #
# can be built by instantiating it once per region with the matching provider  #
# alias. The `aws_rds_global_cluster` resource itself stays in the caller,     #
# because it is a global (region-less) object that must exist exactly once.    #
#                                                                             #
# Compared to `aws/modules/aurora-global` (hardcoded primary + one secondary), #
# this module is the building block used by the multi-region reference         #
# architecture, where Aurora Global can hold up to five secondary regions.     #
###############################################################################

resource "aws_kms_key" "this" {
  description             = "${var.cluster_identifier}-key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.tags
}

###############################################################################
# Subnet group                                                                #
#                                                                             #
# `aws_db_subnet_group` exposes no `vpc_id`: the VPC is derived from the       #
# subnets when the group is created and cannot change afterwards. Terraform    #
# therefore cannot tell that a new subnet list belongs to a different VPC, and #
# plans an in-place `ModifyDBSubnetGroup` that AWS rejects with                #
# `InvalidParameterValue: The new Subnets are not in the same Vpc as the       #
# existing subnet group`. A group that outlives its VPC is then stuck: every   #
# later apply replays the same impossible update and fails.                    #
#                                                                             #
# Putting the VPC in the name makes that dependency visible to Terraform, so a #
# replaced VPC yields a new subnet group instead of an update AWS cannot       #
# honour. The id is kept verbatim rather than hashed so an orphaned group can  #
# still be traced back to the VPC it belonged to. Only the name carries the    #
# id: the description stays stable so the resource keeps a readable label.     #
###############################################################################

resource "aws_db_subnet_group" "this" {
  name        = "${var.cluster_identifier}-${trimprefix(var.vpc_id, "vpc-")}"
  description = "Subnet group for Aurora cluster ${var.cluster_identifier}"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

resource "aws_security_group" "this" {
  name        = "${var.cluster_identifier}-aurora"
  description = "Security group for Aurora cluster ${var.cluster_identifier}"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.port
    to_port     = var.port
    protocol    = "TCP"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow PostgreSQL from every participating region"
  }

  egress {
    from_port   = var.port
    to_port     = var.port
    protocol    = "TCP"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow PostgreSQL to every participating region"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_identifier}-aurora"
  })
}

###############################################################################
# Regional cluster                                                            #
#                                                                             #
# Secondary members intentionally omit master_username / master_password /     #
# database_name / availability_zones: those are inherited from the global      #
# cluster through replication and AWS rejects them on a secondary.            #
###############################################################################

resource "aws_rds_cluster" "this" {
  cluster_identifier        = var.cluster_identifier
  global_cluster_identifier = var.global_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version

  availability_zones = var.is_primary ? var.availability_zones : null
  master_username    = var.is_primary ? var.master_username : null
  master_password    = var.is_primary ? var.master_password : null
  database_name      = var.is_primary ? var.database_name : null

  storage_encrypted       = true
  kms_key_id              = aws_kms_key.this.arn
  vpc_security_group_ids  = [aws_security_group.this.id]
  db_subnet_group_name    = aws_db_subnet_group.this.name
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
  apply_immediately       = var.apply_immediately
  copy_tags_to_snapshot   = true

  iam_database_authentication_enabled = var.iam_auth_enabled

  tags = var.tags

  lifecycle {
    prevent_destroy = false

    # See aws/modules/aurora-global/main.tf for the full rationale. In short,
    # the provider plans to clear these attributes on a secondary member, which
    # AWS translates into PromoteReadReplicaDBCluster and silently detaches the
    # member from the global cluster. Ignoring them is harmless on the primary
    # (they are either unset or driven by the global cluster) which lets a
    # single module serve both roles.
    ignore_changes = [
      replication_source_identifier,
      global_cluster_identifier,
      engine_version,
      availability_zones,
    ]

    # The writer needs credentials, a database name and its availability zones;
    # a secondary inherits all four through replication and AWS rejects them.
    # The same module serves both roles, so the variables default to null and
    # nothing but this stops a primary being planned without them. AWS would
    # otherwise fail the create with a message that names neither the module nor
    # the missing input.
    precondition {
      condition = !var.is_primary || (
        var.master_username != null &&
        var.master_password != null &&
        var.database_name != null &&
        # Null-checked before `length`, which errors on null and would replace
        # the message below with "Invalid function argument".
        var.availability_zones != null && length(var.availability_zones) > 0
      )
      error_message = "is_primary = true requires master_username, master_password, database_name and availability_zones; a secondary member inherits them from the global cluster and must leave them unset."
    }
  }
}

resource "aws_rds_cluster_instance" "this" {
  count = var.num_instances

  cluster_identifier         = aws_rds_cluster.this.id
  identifier                 = "${var.cluster_identifier}-${count.index}"
  engine                     = var.engine
  engine_version             = var.engine_version
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  instance_class             = var.instance_class
  ca_cert_identifier         = var.ca_cert_identifier
  db_subnet_group_name       = aws_db_subnet_group.this.name
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  tags = var.tags

  lifecycle {
    prevent_destroy = false
  }
}
