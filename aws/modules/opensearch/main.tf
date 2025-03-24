resource "aws_opensearch_domain" "opensearch_cluster" {
  tags = var.tags

  domain_name    = var.domain_name
  engine_version = "OpenSearch_${var.engine_version}"

  ip_address_type = var.ip_address_type

  vpc_options {
    subnet_ids         = var.subnet_ids
    security_group_ids = concat([aws_security_group.this.id], var.security_group_ids)
  }

  off_peak_window_options {
    enabled = var.off_peak_window_enabled
  }

  # TODO: integrate logwatch in this component but also in the other for production ready solution

  cluster_config {
    instance_type  = var.instance_type
    instance_count = var.instance_count

    cold_storage_options {
      enabled = var.cold_storage_enabled
    }

    dedicated_master_enabled      = var.dedicated_master_enabled
    dedicated_master_type         = var.dedicated_master_type
    dedicated_master_count        = var.dedicated_master_count
    multi_az_with_standby_enabled = var.multi_az_with_standby_enabled

    warm_enabled = var.warm_enabled
    warm_count   = var.warm_enabled ? var.warm_count : null
    warm_type    = var.warm_enabled ? var.warm_type : null

    zone_awareness_config {
      availability_zone_count = var.zone_awareness_availability_zone_count
    }
    zone_awareness_enabled = var.zone_awareness_enabled
  }

  software_update_options {
    auto_software_update_enabled = var.auto_software_update_enabled
  }

  advanced_security_options {
    enabled                        = var.advanced_security_enabled
    internal_user_database_enabled = var.advanced_security_internal_user_database_enabled

    master_user_options {
      master_user_name     = var.advanced_security_master_user_name
      master_user_password = var.advanced_security_master_user_password

      # Only use master_user_arn if internal_user_database_enabled is false
      master_user_arn = var.advanced_security_internal_user_database_enabled ? null : var.advanced_security_master_user_arn
    }

    anonymous_auth_enabled = var.advanced_security_anonymous_auth_enabled
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.kms.key_id
  }

  node_to_node_encryption {
    enabled = var.node_to_node_encryption_enabled
  }

  ebs_options {
    ebs_enabled = var.ebs_enabled
    iops        = var.ebs_iops
    volume_size = var.ebs_volume_size
    volume_type = var.ebs_volume_type
    throughput  = var.ebs_throughput
  }

  snapshot_options {
    automated_snapshot_start_hour = var.automated_snapshot_start_hour
  }

  auto_tune_options {
    desired_state       = var.auto_tune_options.desired_state
    rollback_on_disable = var.auto_tune_options.rollback_on_disable
  }

  advanced_options = var.advanced_options

  access_policies = var.enable_access_policy ? var.access_policies : null

  dynamic "log_publishing_options" {
    for_each = var.log_types

    content {
      enabled                  = true
      cloudwatch_log_group_arn = join("", aws_cloudwatch_log_group.log_group[*].arn)
      log_type                 = log_publishing_options.value
    }
  }

  domain_endpoint_options {
    enforce_https       = var.domain_endpoint_options.enforce_https
    tls_security_policy = var.domain_endpoint_options.tls_security_policy
  }

  timeouts {
    create = var.create_timeout
  }
}

resource "aws_kms_key" "kms" {
  description             = "${var.domain_name}-key"
  deletion_window_in_days = var.kms_key_delete_window_in_days
  enable_key_rotation     = var.kms_key_enable_key_rotation

  tags = var.kms_key_tags
}
