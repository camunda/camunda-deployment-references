# Tests for the orchestration-cluster module.
#
# Module has many required vars; the variables block below supplies a minimal
# valid fixture so individual run blocks can override only what they care about.

mock_provider "aws" {}

variables {
  aws_region                  = "us-east-1"
  ecs_cluster_id              = "arn:aws:ecs:us-east-1:000000000000:cluster/test"
  vpc_id                      = "vpc-aaaaaaaa"
  vpc_private_subnets         = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
  prefix                      = "test-oc"
  ecs_task_execution_role_arn = "arn:aws:iam::000000000000:role/test-exec"
}

run "internal_nlb_raft_listener_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.raft_26502) == 0
    error_message = "Internal NLB Raft listener should be empty when enable_internal_nlb_raft_listener defaults to false"
  }
}

run "internal_nlb_raft_listener_created_when_enabled" {
  command = plan

  variables {
    enable_internal_nlb_raft_listener = true
    nlb_arn                           = "arn:aws:elasticloadbalancing:us-east-1:000000000000:loadbalancer/net/test/x"
  }

  assert {
    condition     = length(aws_lb_listener.raft_26502) == 1
    error_message = "Internal NLB Raft listener should be created when enable_internal_nlb_raft_listener = true"
  }
}

run "alb_management_rule_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_lb_listener_rule.http_management) == 0
    error_message = "ALB management rule should be empty when enable_alb_http_management_listener_rule defaults to false"
  }
}

run "alb_management_rule_created_when_enabled" {
  command = plan

  variables {
    enable_alb_http_management_listener_rule = true
    alb_listener_http_management_arn         = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/test/x/y"
  }

  # The module's check "monitoring_port_9600_exposure" intentionally warns when
  # this toggle is on (port 9600 should not normally be exposed publicly).
  # That's the expected behavior of the check block — pin it in expect_failures.
  expect_failures = [
    check.monitoring_port_9600_exposure,
  ]

  assert {
    condition     = length(aws_lb_listener_rule.http_management) == 1
    error_message = "ALB management rule should be created when enable_alb_http_management_listener_rule = true"
  }
}

run "prefix_used_in_resource_names" {
  command = plan

  assert {
    condition     = strcontains(aws_cloudwatch_log_group.orchestration_cluster_log_group.name, "test-oc")
    error_message = "CloudWatch log group name should include the prefix"
  }
}
