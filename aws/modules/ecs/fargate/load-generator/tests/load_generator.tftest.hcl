# Tests for the load-generator module.
#
# The module replaces the absorbed starter/worker pair, which pulled two
# private images from registry.camunda.cloud, with the public community
# benchmark. The cases pinned here are the ones that decide whether a copy of
# this reference can generate load at all: the client has to reach the cluster,
# it has to authenticate the way the ECS reference actually runs (basic auth,
# no Management Identity), and workers have to run alongside the starter or the
# rate stops meaning anything.

mock_provider "aws" {}

variables {
  aws_region                  = "us-east-1"
  ecs_cluster_id              = "arn:aws:ecs:us-east-1:000000000000:cluster/test"
  vpc_id                      = "vpc-aaaaaaaa"
  vpc_private_subnets         = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
  prefix                      = "test-lg"
  ecs_task_execution_role_arn = "arn:aws:iam::000000000000:role/test-exec"
  camunda_host                = "orchestration-cluster.test-oc.service.local"
  auth_password_secret_arn    = "arn:aws:secretsmanager:us-east-1:000000000000:secret:test-pw"
}

run "prefix_used_in_resource_names" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.load_generator.family == "test-lg-load-generator"
    error_message = "ECS task definition family should be derived from the prefix"
  }

  assert {
    condition     = aws_ecs_service.load_generator.name == "test-lg-load-generator"
    error_message = "ECS service name should be derived from the prefix"
  }
}

run "uses_a_publicly_pullable_image_by_default" {
  command = plan

  # The whole reason this module exists rather than a copy of the absorbed
  # starter/worker pair: anything in this repository is meant to be pulled by
  # someone outside Camunda.
  assert {
    condition     = startswith(var.image, "camundacommunityhub/camunda-8-benchmark")
    error_message = "The default image must be the public community benchmark, not a private registry image"
  }
}

run "client_addresses_derived_from_the_camunda_host" {
  command = plan

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "http://orchestration-cluster.test-oc.service.local:26500")
    error_message = "The gRPC address should be derived from camunda_host and the gRPC port"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "http://orchestration-cluster.test-oc.service.local:8080/rest")
    error_message = "The REST address should be derived from camunda_host and the REST port"
  }
}

run "basic_auth_password_injected_as_a_secret" {
  command = plan

  # The password must reach the container through the ECS secrets mechanism,
  # never as a plain environment variable in the task definition.
  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "arn:aws:secretsmanager:us-east-1:000000000000:secret:test-pw")
    error_message = "The auth password secret ARN should be wired into the task definition"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "CAMUNDA_CLIENT_AUTH_PASSWORD")
    error_message = "The container should receive CAMUNDA_CLIENT_AUTH_PASSWORD"
  }
}

run "workers_run_alongside_the_starter_by_default" {
  command = plan

  # Without workers the started instances pile up as active work and the export
  # rate stops tracking the start rate, which is the number this exists to hold
  # steady.
  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_START_WORKERS\",\"value\":\"true\"}")
    error_message = "BENCHMARK_START_WORKERS should default to true"
  }
}

run "workers_can_be_turned_off" {
  command = plan

  variables {
    start_workers = false
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_START_WORKERS\",\"value\":\"false\"}")
    error_message = "BENCHMARK_START_WORKERS should follow start_workers"
  }
}

run "extra_environment_variables_are_appended" {
  command = plan

  variables {
    extra_environment_variables = [
      { name = "BENCHMARK_CUSTOM", value = "custom-value" },
    ]
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "custom-value")
    error_message = "extra_environment_variables should reach the container definition"
  }
}

run "rejects_a_zero_start_rate" {
  command = plan

  variables {
    start_rate = 0
  }

  expect_failures = [var.start_rate]
}

run "rejects_an_unknown_auth_method" {
  command = plan

  variables {
    auth_method = "kerberos"
  }

  expect_failures = [var.auth_method]
}

run "rejects_oidc_because_it_is_not_implemented" {
  command = plan

  # The module exposes no client credential inputs, so accepting oidc would
  # silently fall through to the image defaults instead of configuring it.
  variables {
    auth_method = "oidc"
  }

  expect_failures = [var.auth_method]
}

run "rejects_basic_auth_without_a_password_secret" {
  command = plan

  variables {
    auth_method              = "basic"
    auth_password_secret_arn = ""
  }

  expect_failures = [aws_ecs_task_definition.load_generator]
}

run "no_auth_needs_no_password_secret" {
  command = plan

  variables {
    auth_method              = "none"
    auth_password_secret_arn = ""
  }

  assert {
    condition     = !strcontains(aws_ecs_task_definition.load_generator.container_definitions, "CAMUNDA_CLIENT_AUTH_PASSWORD")
    error_message = "No auth secret should be wired when auth_method is none"
  }
}
