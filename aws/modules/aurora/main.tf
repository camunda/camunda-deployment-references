# Provision an RDS Aurora cluster suitable for operating within our VPC and VPN connectivity.

resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier = var.cluster_name
  availability_zones = var.availability_zones

  engine          = var.engine
  engine_version  = var.engine_version
  master_password = var.password
  master_username = var.username
  database_name   = var.default_database_name

  iam_database_authentication_enabled = var.iam_auth_enabled

  # don't assign twice the roles, otherwise you may encounter conflicts
  iam_roles = var.iam_roles # only needed if wanted to grant access from Aurora to e.g. S3

  vpc_security_group_ids = [aws_security_group.this.id]
  db_subnet_group_name   = aws_db_subnet_group.this.name
  skip_final_snapshot    = true
  apply_immediately      = true
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.this.arn

  tags                  = var.tags
  copy_tags_to_snapshot = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_kms_key" "this" {
  description             = "${var.cluster_name}-key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  count = var.num_instances

  cluster_identifier = var.cluster_name
  identifier         = "${var.cluster_name}-${count.index}"

  ca_cert_identifier         = var.ca_cert_identifier
  engine                     = var.engine
  engine_version             = var.engine_version
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  instance_class             = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.this.name

  apply_immediately = true

  tags = var.tags

  copy_tags_to_snapshot = true

  lifecycle {
    prevent_destroy = false
  }

  # add hard dependency on cluster as the instance can only be created after the cluster
  # this is required for the initial terraform apply to not fail due to the cluster not existing yet
  depends_on = [aws_rds_cluster.aurora_cluster]
}

resource "aws_db_subnet_group" "this" {
  name = var.cluster_name

  description = "For Aurora cluster ${var.cluster_name}"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}
