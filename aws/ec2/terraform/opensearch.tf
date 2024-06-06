resource "aws_opensearch_domain" "opensearch_cluster" {
  count = var.enable_opensearch ? 1 : 0

  domain_name    = "${var.prefix}-os-cluster"
  engine_version = "OpenSearch_2.5"

  vpc_options {
    subnet_ids = module.vpc.private_subnets
    security_group_ids = [
      aws_security_group.allow_any_traffic_within_vpc.id,
    ]
  }

  cluster_config {
    instance_type  = "t3.small.search" # "r6g.large.search"
    instance_count = var.instance_count
    warm_enabled   = false

    zone_awareness_config {
      availability_zone_count = 3
    }
    zone_awareness_enabled = true
  }

  advanced_security_options {
    enabled                        = false
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = "camunda"
      master_user_password = "camundarocks123"
    }
    anonymous_auth_enabled = false
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.main.arn
  }

  node_to_node_encryption {
    enabled = true
  }

  ebs_options {
    ebs_enabled = true
    volume_size = "50"
    volume_type = "gp3"
    throughput  = "125"
  }

  snapshot_options {
    automated_snapshot_start_hour = 0
  }
  advanced_options = {
    "rest.action.multi.allow_explicit_index" = true
  }
  dynamic "log_publishing_options" {
    for_each = var.opensearch_log_types

    content {
      enabled = var.enable_opensearch_logging
      # in case it's disabled, we provide a dummy ARN to avoid errors
      cloudwatch_log_group_arn = var.enable_opensearch_logging ? join("", aws_cloudwatch_log_group.os_log_group[*].arn) : "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:doesnotexistbutrequired"
      log_type                 = log_publishing_options.value
    }
  }

  access_policies = <<CONFIG
  {
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "es:*",
      "Resource": "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.prefix}-os-cluster/*"
    }
  ]
}
CONFIG

  timeouts {
    create = "2h"
  }

}

resource "aws_cloudwatch_log_group" "os_log_group" {
  count = var.enable_opensearch && var.enable_opensearch_logging ? 1 : 0
  name  = "${var.prefix}-os-logs"
}

data "aws_iam_policy_document" "os_logging_policy_document" {
  count = var.enable_opensearch && var.enable_opensearch_logging ? 1 : 0
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["es.amazonaws.com"]
    }

    actions = [
      "logs:PutLogEvents",
      "logs:PutLogEventsBatch",
      "logs:CreateLogStream",
    ]

    resources = ["arn:aws:logs:*"]
  }
}

resource "aws_cloudwatch_log_resource_policy" "os_logging_policy" {
  count           = var.enable_opensearch && var.enable_opensearch_logging ? 1 : 0
  policy_name     = "${var.prefix}-os-logging-policy"
  policy_document = join("", data.aws_iam_policy_document.os_logging_policy_document[*].json)
}
