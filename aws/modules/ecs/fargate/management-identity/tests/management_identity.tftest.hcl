# Tests for the management-identity module.

mock_provider "aws" {}

variables {
  aws_region                  = "us-east-1"
  ecs_cluster_id              = "arn:aws:ecs:us-east-1:000000000000:cluster/test"
  vpc_id                      = "vpc-aaaaaaaa"
  vpc_private_subnets         = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
  prefix                      = "test-idty"
  ecs_task_execution_role_arn = "arn:aws:iam::000000000000:role/test-exec"
}

run "alb_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_lb_listener_rule.http_webapp) == 0
    error_message = "ALB listener rule must NOT be created by default (enable_alb_http_webapp_listener_rule defaults to false)"
  }

  assert {
    condition     = length(aws_lb_target_group.main) == 0
    error_message = "ALB target group must NOT be created when ALB exposure is disabled"
  }
}

run "alb_created_when_enabled" {
  command = plan

  variables {
    enable_alb_http_webapp_listener_rule = true
    alb_listener_http_webapp_arn         = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/test/x/y"
  }

  assert {
    condition     = length(aws_lb_listener_rule.http_webapp) == 1
    error_message = "ALB listener rule must be created when enable_alb_http_webapp_listener_rule = true"
  }

  assert {
    condition     = length(aws_lb_target_group.main) == 1
    error_message = "ALB target group must be created when ALB exposure is enabled"
  }
}

run "prefix_used_in_resource_names" {
  command = plan

  assert {
    condition     = strcontains(aws_ecs_task_definition.management_identity.family, "test-idty")
    error_message = "ECS task definition family should include the prefix"
  }
}

run "extra_task_role_attachments_count_matches_var" {
  command = plan

  variables {
    extra_task_role_attachments = [
      "arn:aws:iam::000000000000:policy/extra-1",
      "arn:aws:iam::000000000000:policy/extra-2",
    ]
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.task_role_policy_attachment) == 2
    error_message = "extra_task_role_attachments should produce one IAM attachment per ARN"
  }
}
