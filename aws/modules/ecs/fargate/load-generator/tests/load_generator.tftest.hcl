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
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_STARTWORKERS\",\"value\":\"true\"}")
    error_message = "BENCHMARK_STARTWORKERS should default to true"
  }
}

# Spring binds a camelCase property such as benchmark.startPiPerSecond from
# BENCHMARK_STARTPIPERSECOND only. An underscore between the words makes it a
# different property, so the variable is ignored in silence and the image keeps
# its packaged default of 1 process instance per second. Verified against
# camundacommunityhub/camunda-8-benchmark:main through /actuator/env: the
# underscore spelling left benchmark.startPiPerSecond at 1, the contiguous
# spelling bound 150.
#
# kebab-case properties are the opposite: camunda.client.zeebe.grpc-address
# binds from CAMUNDA_CLIENT_ZEEBE_GRPC_ADDRESS, and not from the contiguous
# spelling. Both shapes are pinned below.
run "benchmark_settings_use_the_env_spelling_spring_actually_binds" {
  command = plan

  variables {
    start_rate                   = 150
    task_completion_delay        = 50
    warmup_phase_duration_millis = 10000
    multiple_job_types           = 0
    bpmn_process_id              = "benchmark"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_STARTPIPERSECOND\",\"value\":\"150\"}")
    error_message = "The start rate must be BENCHMARK_STARTPIPERSECOND; BENCHMARK_START_PI_PER_SECOND is silently ignored"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_TASKCOMPLETIONDELAY\",\"value\":\"50\"}")
    error_message = "The completion delay must be BENCHMARK_TASKCOMPLETIONDELAY"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_WARMUPPHASEDURATIONMILLIS\",\"value\":\"10000\"}")
    error_message = "The warmup must be BENCHMARK_WARMUPPHASEDURATIONMILLIS"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_STARTRATEADJUSTMENTSTRATEGY\",\"value\":\"none\"}")
    error_message = "The rate strategy must be BENCHMARK_STARTRATEADJUSTMENTSTRATEGY"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_BPMNPROCESSID\",\"value\":\"benchmark\"}")
    error_message = "The process id must be BENCHMARK_BPMNPROCESSID"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_MULTIPLEJOBTYPES\",\"value\":\"0\"}")
    error_message = "multiple_job_types = 0 must reach the container, meaning the worker subscribes to job_type verbatim"
  }

  # No BENCHMARK_ key may contain an underscore after the prefix.
  assert {
    condition     = length(regexall("\"BENCHMARK_[A-Z]+_[A-Z]", aws_ecs_task_definition.load_generator.container_definitions)) == 0
    error_message = "A BENCHMARK_* variable still uses the underscore spelling, which Spring does not bind"
  }

  # The client properties are kebab-case and need exactly the opposite shape.
  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "CAMUNDA_CLIENT_ZEEBE_GRPC_ADDRESS")
    error_message = "camunda.client.zeebe.grpc-address binds from the underscore spelling"
  }
}

run "worker_concurrency_is_configurable" {
  command = plan

  variables {
    max_jobs_active   = 60
    execution_threads = 10
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"CAMUNDA_CLIENT_ZEEBE_DEFAULTS_MAX_JOBS_ACTIVE\",\"value\":\"60\"}")
    error_message = "max_jobs_active should reach the container as the kebab-shaped env var"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"CAMUNDA_CLIENT_ZEEBE_EXECUTION_THREADS\",\"value\":\"10\"}")
    error_message = "execution_threads should reach the container as the kebab-shaped env var"
  }
}

run "payload_is_configurable" {
  command = plan

  variables {
    payload_path = "classpath:bpmn/typical_payload.json"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_PAYLOADPATH\",\"value\":\"classpath:bpmn/typical_payload.json\"}")
    error_message = "payload_path should reach the container as BENCHMARK_PAYLOADPATH"
  }
}

run "single_task_workload_is_deployed_by_default" {
  command = plan

  # The absorbed benchmark drove a one-service-task process. The image bundles
  # only multi-task ones, so the module ships its own and renders it into the
  # task, the same way the monitoring module renders its Prometheus config.
  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "BENCHMARK_BPMNRESOURCE")
    error_message = "The generator should deploy a known process rather than the image's default"
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "one-task.bpmn")
    error_message = "The bundled single-task process should be the default workload"
  }
}

run "survives_a_cluster_that_is_not_registered_yet" {
  command = plan

  # The image treats a failed initial deployment as fatal. On a cold apply the
  # Orchestration Cluster has no Cloud Map record yet, so the first launch exits
  # on "Unable to resolve host"; ECS replaces the task a handful of times, the
  # deployment circuit breaker gives up, and the service is left with no
  # generator and no further logs. Observed on a real apply before this retry
  # existed: three launches a minute apart, then twenty-one minutes of silence.
  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "until java org.springframework.boot.loader.launch.JarLauncher")
    error_message = "The container must retry the launcher, or a cold start leaves the generator permanently stopped"
  }
}

run "workers_can_be_turned_off" {
  command = plan

  variables {
    start_workers = false
  }

  assert {
    condition     = strcontains(aws_ecs_task_definition.load_generator.container_definitions, "{\"name\":\"BENCHMARK_STARTWORKERS\",\"value\":\"false\"}")
    error_message = "BENCHMARK_STARTWORKERS should follow start_workers"
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
