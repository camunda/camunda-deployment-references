# Tests for the monitoring module.
#
# The module carries a long-lived Prometheus that discovers orchestration
# clusters through Cloud Map, so the cases worth pinning are the ones a
# consumer can get wrong: the discovery sidecar must ship with the server, the
# endpoint must stay private unless a listener is handed in on purpose, and the
# retention window must be a duration Prometheus will actually accept.

mock_provider "aws" {}

variables {
  aws_region                  = "us-east-1"
  ecs_cluster_id              = "arn:aws:ecs:us-east-1:000000000000:cluster/test"
  vpc_id                      = "vpc-aaaaaaaa"
  vpc_private_subnets         = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
  prefix                      = "test-mon"
  ecs_task_execution_role_arn = "arn:aws:iam::000000000000:role/test-exec"
}

run "prefix_used_in_resource_names" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.prometheus.family == "test-mon-prometheus"
    error_message = "ECS task definition family should be derived from the prefix"
  }

  assert {
    condition     = aws_ecs_service.prometheus.name == "test-mon-prometheus"
    error_message = "ECS service name should be derived from the prefix"
  }
}

run "discovery_sidecar_ships_with_the_server" {
  command = plan

  # Prometheus reads a file the sidecar writes. Shipping the server without the
  # sidecar yields a permanently empty target list rather than a visible error,
  # so the two container definitions are pinned together.
  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "\"name\":\"discovery\"")
    error_message = "The task definition should carry the Cloud Map discovery sidecar"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "\"name\":\"prometheus\"")
    error_message = "The task definition should carry the Prometheus container"
  }
}

run "scraped_series_carry_no_task_ip" {
  command = plan

  # Series leave the VPC when a run exports them for later analysis. The
  # scrape target is a task IP, so `instance` is rewritten to the task id the
  # discovery sidecar already puts in `pod`.
  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "source_labels: [pod]")
    error_message = "The scrape config should rewrite instance from the pod label"
  }
}

run "discovery_scope_is_configurable" {
  command = plan

  variables {
    discovery_namespace_suffix = "-custom.service.local"
    discovery_service_name     = "my-cluster"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "-custom.service.local")
    error_message = "The sidecar should receive the configured Cloud Map namespace suffix"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "my-cluster")
    error_message = "The sidecar should receive the configured Cloud Map service name"
  }
}

run "endpoint_is_private_by_default" {
  command = plan

  # The source stack put Prometheus behind an internet-facing ALB. Defaulting
  # to no listener rule keeps an unauthenticated metrics endpoint off the
  # public internet for anyone copying this module.
  assert {
    condition     = length(aws_lb_target_group.prometheus) == 0
    error_message = "No target group should be created unless an ALB listener is supplied"
  }

  assert {
    condition     = length(aws_lb_listener_rule.prometheus) == 0
    error_message = "No listener rule should be created by default"
  }
}

run "alb_rule_created_when_listener_supplied" {
  command = plan

  variables {
    enable_alb_http_listener_rule = true
    alb_listener_http_arn         = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/test/x/y"
  }

  assert {
    condition     = length(aws_lb_target_group.prometheus) == 1
    error_message = "A target group should be created when the ALB listener rule is enabled"
  }

  assert {
    condition     = length(aws_lb_listener_rule.prometheus) == 1
    error_message = "A listener rule should be created when the ALB listener rule is enabled"
  }

  # An ALB forwards the matched path unchanged, so the server has to be told
  # which prefix it is served under or every request under it answers 404.
  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "--web.route-prefix=/prometheus")
    error_message = "Prometheus should be started under the same prefix the listener rule matches"
  }

  assert {
    condition     = aws_lb_target_group.prometheus[0].health_check[0].path == "/prometheus/-/healthy"
    error_message = "The health check must be probed under the route prefix, not at the root"
  }

  # The listener this is meant to be attached to is the ECS reference's shared
  # web listener, where the orchestration-cluster module pins its own rule at
  # priority 100 (orchestration-cluster/lb.tf). A default of 100 here means the
  # documented way of exposing Prometheus fails on a duplicate priority.
  assert {
    condition     = aws_lb_listener_rule.prometheus[0].priority != 100
    error_message = "The default listener rule priority must not be the one orchestration-cluster already takes"
  }
}

run "route_prefix_not_applied_without_a_listener" {
  command = plan

  # Without the ALB the way in is the private DNS name, where a prefix would
  # only make the server harder to reach.
  assert {
    condition     = !strcontains(aws_ecs_task_definition.prometheus.container_definitions, "--web.route-prefix")
    error_message = "No route prefix should be set when Prometheus is not behind a listener"
  }
}

run "log_group_created_when_not_supplied" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_group.monitoring) == 1
    error_message = "The module should create its own log group when none is supplied"
  }
}

run "log_group_reused_when_supplied" {
  command = plan

  variables {
    log_group_name = "/ecs/existing"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.monitoring) == 0
    error_message = "The module should not create a log group when one is supplied"
  }
}

run "rejects_a_retention_window_prometheus_cannot_parse" {
  command = plan

  variables {
    retention_time = "one week"
  }

  expect_failures = [var.retention_time]
}

run "rejects_an_empty_discovery_namespace_suffix" {
  command = plan

  variables {
    discovery_namespace_suffix = ""
  }

  expect_failures = [var.discovery_namespace_suffix]
}

run "rejects_an_alb_rule_without_a_listener" {
  command = plan

  # Enabling the rule without a listener ARN would otherwise fail deep inside
  # the provider with an unhelpful message.
  variables {
    enable_alb_http_listener_rule = true
    alb_listener_http_arn         = ""
  }

  expect_failures = [aws_lb_listener_rule.prometheus]
}

run "series_export_off_by_default" {
  command = plan

  assert {
    condition     = !strcontains(aws_ecs_task_definition.prometheus.container_definitions, "\"name\":\"upload\"")
    error_message = "No upload sidecar should ship unless export_gcs_bucket is set"
  }

  assert {
    condition     = !strcontains(aws_ecs_task_definition.prometheus.container_definitions, "export-series.sh")
    error_message = "Prometheus should not dump its series unless export_gcs_bucket is set"
  }
}

run "series_export_ships_dumper_and_uploader" {
  command = plan

  variables {
    export_gcs_bucket            = "results"
    export_namespace             = "ecs-ci-1"
    export_gcp_credential_config = "{\"type\":\"external_account\"}"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "\"name\":\"upload\"")
    error_message = "The upload sidecar should ship when export_gcs_bucket is set"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "export-series.sh")
    error_message = "Prometheus should dump its series periodically when export_gcs_bucket is set"
  }

  # A long-running load test must reach the dashboard while it runs: one batch
  # every 15 minutes, uploaded as soon as it is dumped.
  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "{\"name\":\"EXPORT_INTERVAL_SECONDS\",\"value\":\"900\"}")
    error_message = "The series should be dumped every 15 minutes by default"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.prometheus.container_definitions, "{\"name\":\"UPLOAD_POLL_SECONDS\",\"value\":\"60\"}")
    error_message = "The upload sidecar should poll every minute, so a batch does not wait for the next dump"
  }
}

run "rejects_an_export_without_a_namespace" {
  command = plan

  variables {
    export_gcs_bucket            = "results"
    export_gcp_credential_config = "{\"type\":\"external_account\"}"
  }

  expect_failures = [var.export_namespace]
}

run "rejects_a_credential_config_that_is_not_external_account" {
  command = plan

  variables {
    export_gcs_bucket            = "results"
    export_namespace             = "ecs-ci-1"
    export_gcp_credential_config = "{\"type\":\"service_account\"}"
  }

  expect_failures = [var.export_gcp_credential_config]
}

run "rejects_an_export_interval_under_a_minute" {
  command = plan

  variables {
    export_interval_seconds = 0
  }

  expect_failures = [var.export_interval_seconds]
}

run "registry_credentials_stay_off_the_upload_sidecar" {
  command = plan

  # The credentials are for a private Prometheus mirror; the upload sidecar
  # pulls a public image and must not need them.
  variables {
    registry_credentials_arn     = "arn:aws:secretsmanager:us-east-1:000000000000:secret:reg"
    export_gcs_bucket            = "results"
    export_namespace             = "ecs-ci-1"
    export_gcp_credential_config = "{\"type\":\"external_account\"}"
  }

  assert {
    condition     = length([for c in jsondecode(aws_ecs_task_definition.prometheus.container_definitions) : c if c.name == "upload" && can(c.repositoryCredentials)]) == 0
    error_message = "The upload sidecar should not carry the Prometheus registry credentials"
  }
}
