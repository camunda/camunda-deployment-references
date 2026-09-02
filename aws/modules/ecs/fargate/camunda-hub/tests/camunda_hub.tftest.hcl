# Tests for the camunda-hub module.

mock_provider "aws" {}

variables {
  aws_region                  = "us-east-1"
  ecs_cluster_id              = "arn:aws:ecs:us-east-1:000000000000:cluster/test"
  vpc_id                      = "vpc-aaaaaaaa"
  vpc_private_subnets         = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
  prefix                      = "test-hub"
  ecs_task_execution_role_arn = "arn:aws:iam::000000000000:role/test-exec"
}

run "task_definition_has_two_containers" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.camunda_hub.container_definitions)) == 2
    error_message = "Camunda Hub task definition must have exactly two containers (restapi + websockets)"
  }
}

run "container_names_use_camunda_hub_prefix" {
  command = plan

  assert {
    condition = alltrue([
      for c in jsondecode(aws_ecs_task_definition.camunda_hub.container_definitions) :
      strcontains(c.name, "camunda-hub")
    ])
    error_message = "Both container names must use the camunda-hub prefix"
  }
}

run "family_uses_prefix" {
  command = plan

  assert {
    condition     = strcontains(aws_ecs_task_definition.camunda_hub.family, "test-hub")
    error_message = "ECS task definition family should include the prefix"
  }
}

run "alb_listener_rules_created_by_default" {
  command = plan

  variables {
    alb_listener_http_webapp_arn = "arn:aws:elasticloadbalancing:us-east-1:000000000000:listener/app/test/x/y"
  }

  assert {
    condition     = length(aws_lb_listener_rule.hub) == 1 && length(aws_lb_listener_rule.hub_ws) == 1
    error_message = "Both ALB listener rules should be created by default"
  }
}

run "alb_listener_rules_skipped_when_disabled" {
  command = plan

  variables {
    enable_alb_http_webapp_listener_rule = false
  }

  assert {
    condition     = length(aws_lb_listener_rule.hub) == 0 && length(aws_lb_listener_rule.hub_ws) == 0
    error_message = "ALB listener rules should be empty when enable_alb_http_webapp_listener_rule = false"
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
