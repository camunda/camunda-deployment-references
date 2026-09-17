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
