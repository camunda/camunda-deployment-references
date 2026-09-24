# Tests for the keycloak module.

mock_provider "aws" {}

variables {
  aws_region                  = "us-east-1"
  ecs_cluster_id              = "arn:aws:ecs:us-east-1:000000000000:cluster/test"
  vpc_id                      = "vpc-aaaaaaaa"
  vpc_private_subnets         = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
  prefix                      = "test-kc"
  ecs_task_execution_role_arn = "arn:aws:iam::000000000000:role/test-exec"
}

run "alb_disabled_by_default" {
  command = plan
  assert {
    condition     = length(aws_lb_listener_rule.http_webapp) == 0
    error_message = "ALB listener rule must NOT be created by default"
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
    error_message = "ALB listener rule must be created when enabled"
  }
}

run "prefix_used_in_resource_names" {
  command = plan
  assert {
    condition     = strcontains(aws_ecs_task_definition.keycloak.family, "test-kc")
    error_message = "ECS task definition family should include the prefix"
  }
}

run "realm_import_disabled_by_default" {
  command = plan
  assert {
    condition     = !strcontains(aws_ecs_task_definition.keycloak.container_definitions, "--import-realm")
    error_message = "Keycloak must start without --import-realm when realm import is disabled (default)"
  }
}

run "realm_import_changes_startup_command" {
  command = plan
  variables {
    enable_realm_import = true
    secrets = [
      { name = "KEYCLOAK_REALM_IMPORT_JSON", valueFrom = "arn:aws:secretsmanager:us-east-1:000000000000:secret:realm-abc123" },
    ]
  }
  assert {
    condition     = strcontains(aws_ecs_task_definition.keycloak.container_definitions, "--import-realm")
    error_message = "With enable_realm_import, the container must start Keycloak with --import-realm"
  }
  assert {
    condition     = strcontains(aws_ecs_task_definition.keycloak.container_definitions, "KEYCLOAK_REALM_IMPORT_JSON")
    error_message = "With enable_realm_import, the startup command must consume KEYCLOAK_REALM_IMPORT_JSON"
  }
}

run "realm_import_requires_import_secret" {
  command = plan
  variables {
    enable_realm_import = true
    secrets             = []
  }
  # Enabling realm import without the KEYCLOAK_REALM_IMPORT_JSON secret must fail at
  # plan time rather than at container startup (unbound variable under `set -u`).
  expect_failures = [var.enable_realm_import]
}

run "extra_task_role_attachments_count_matches_var" {
  command = plan
  variables {
    extra_task_role_attachments = ["arn:aws:iam::000000000000:policy/extra-1"]
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.task_role_policy_attachment) == 1
    error_message = "extra_task_role_attachments should produce one IAM attachment per ARN"
  }
}
