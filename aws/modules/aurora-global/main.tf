# Aurora Global Database spanning two regions.
# Primary cluster (writer) in region 0, secondary cluster (read replicas) in region 1.
# On failover, the secondary cluster is promoted to writer.

################################
# Global Cluster              #
################################

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = var.global_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
}

################################
# Primary Cluster (Region 0) #
################################

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "${var.primary_cluster_name}-key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = var.primary_cluster_name
  description = "Subnet group for Aurora primary cluster ${var.primary_cluster_name}"
  subnet_ids  = var.primary_subnet_ids

  tags = var.tags
}

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${var.primary_cluster_name}-aurora"
  description = "Security group for Aurora primary cluster"
  vpc_id      = var.primary_vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "TCP"
    cidr_blocks = var.primary_cidr_blocks
    description = "Allow PostgreSQL from allowed CIDRs"
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "TCP"
    cidr_blocks = var.primary_cidr_blocks
    description = "Allow PostgreSQL to allowed CIDRs"
  }

  tags = merge(var.tags, {
    Name = "${var.primary_cluster_name}-aurora"
  })
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = var.primary_cluster_name
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = var.engine
  engine_version            = var.engine_version
  availability_zones        = var.primary_availability_zones
  master_username           = var.master_username
  master_password           = var.master_password
  database_name             = var.database_name
  storage_encrypted         = true
  kms_key_id                = aws_kms_key.primary.arn
  vpc_security_group_ids    = [aws_security_group.primary.id]
  db_subnet_group_name      = aws_db_subnet_group.primary.name
  backup_retention_period   = var.backup_retention_period
  skip_final_snapshot       = true
  apply_immediately         = true
  copy_tags_to_snapshot     = true

  iam_database_authentication_enabled = var.iam_auth_enabled

  tags = var.tags

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary

  count = var.primary_num_instances

  cluster_identifier         = aws_rds_cluster.primary.id
  identifier                 = "${var.primary_cluster_name}-${count.index}"
  engine                     = var.engine
  engine_version             = var.engine_version
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  instance_class             = var.instance_class
  ca_cert_identifier         = var.ca_cert_identifier
  db_subnet_group_name       = aws_db_subnet_group.primary.name
  apply_immediately          = true
  copy_tags_to_snapshot      = true

  tags = var.tags

  lifecycle {
    prevent_destroy = false
  }
}

################################
# Secondary Cluster (Region 1)#
################################

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "${var.secondary_cluster_name}-key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = var.secondary_cluster_name
  description = "Subnet group for Aurora secondary cluster ${var.secondary_cluster_name}"
  subnet_ids  = var.secondary_subnet_ids

  tags = var.tags
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${var.secondary_cluster_name}-aurora"
  description = "Security group for Aurora secondary cluster"
  vpc_id      = var.secondary_vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "TCP"
    cidr_blocks = var.secondary_cidr_blocks
    description = "Allow PostgreSQL from allowed CIDRs"
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "TCP"
    cidr_blocks = var.secondary_cidr_blocks
    description = "Allow PostgreSQL to allowed CIDRs"
  }

  tags = merge(var.tags, {
    Name = "${var.secondary_cluster_name}-aurora"
  })
}

# Secondary cluster: no master_username, master_password, or database_name
# These are inherited from the global cluster via replication.
resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = var.secondary_cluster_name
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = var.engine
  engine_version            = var.engine_version
  storage_encrypted         = true
  kms_key_id                = aws_kms_key.secondary.arn
  vpc_security_group_ids    = [aws_security_group.secondary.id]
  db_subnet_group_name      = aws_db_subnet_group.secondary.name
  skip_final_snapshot       = true
  apply_immediately         = true
  copy_tags_to_snapshot     = true

  iam_database_authentication_enabled = var.iam_auth_enabled

  tags = var.tags

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary

  count = var.secondary_num_instances

  cluster_identifier         = aws_rds_cluster.secondary.id
  identifier                 = "${var.secondary_cluster_name}-${count.index}"
  engine                     = var.engine
  engine_version             = var.engine_version
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  instance_class             = var.instance_class
  ca_cert_identifier         = var.ca_cert_identifier
  db_subnet_group_name       = aws_db_subnet_group.secondary.name
  apply_immediately          = true
  copy_tags_to_snapshot      = true

  tags = var.tags

  lifecycle {
    prevent_destroy = false
  }
}
