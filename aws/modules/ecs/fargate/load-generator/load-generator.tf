locals {
  log_group_name = var.log_group_name != "" ? var.log_group_name : aws_cloudwatch_log_group.load_generator[0].name

  grpc_address = "http://${var.camunda_host}:${var.camunda_grpc_port}"
  rest_address = "http://${var.camunda_host}:${var.camunda_rest_port}/rest"

  uses_basic_auth = var.auth_method == "basic"

  # Only the password travels as an ECS secret; everything else is plain
  # configuration and stays readable in the task definition.
  auth_secrets = local.uses_basic_auth ? [
    {
      name      = "CAMUNDA_CLIENT_AUTH_PASSWORD"
      valueFrom = var.auth_password_secret_arn
    }
  ] : []

  auth_environment = local.uses_basic_auth ? [
    { name = "CAMUNDA_CLIENT_AUTH_METHOD", value = "basic" },
    { name = "CAMUNDA_CLIENT_AUTH_USERNAME", value = var.auth_username },
  ] : []

  # Left out when empty so the image's own defaults apply rather than an empty
  # string overriding them.
  optional_environment = concat(
    var.bpmn_process_id != "" ? [{ name = "BENCHMARK_BPMNPROCESSID", value = var.bpmn_process_id }] : [],
    var.bpmn_resource != "" ? [{ name = "BENCHMARK_BPMNRESOURCE", value = var.bpmn_resource }] : [],
    var.payload_path != "" ? [{ name = "BENCHMARK_PAYLOADPATH", value = var.payload_path }] : [],
    var.max_jobs_active > 0 ? [{ name = "CAMUNDA_CLIENT_ZEEBE_DEFAULTS_MAX_JOBS_ACTIVE", value = tostring(var.max_jobs_active) }] : [],
    var.execution_threads > 0 ? [{ name = "CAMUNDA_CLIENT_ZEEBE_EXECUTION_THREADS", value = tostring(var.execution_threads) }] : [],
  )

  # Spring resolves a camelCase property such as benchmark.startPiPerSecond from
  # BENCHMARK_STARTPIPERSECOND. Inserting underscores between the words names a
  # different property, which binds to nothing and leaves the packaged default
  # in place, so the generator would quietly run at 1 process instance per
  # second. Kebab-case properties such as camunda.client.zeebe.grpc-address are
  # the other way round and do take the underscores. Both spellings below were
  # checked against the image through /actuator/env.
  environment = concat(
    [
      { name = "CAMUNDA_CLIENT_MODE", value = "self-managed" },
      { name = "CAMUNDA_CLIENT_ZEEBE_GRPC_ADDRESS", value = local.grpc_address },
      { name = "CAMUNDA_CLIENT_ZEEBE_REST_ADDRESS", value = local.rest_address },
      { name = "CAMUNDA_CLIENT_ZEEBE_PREFER_REST_OVER_GRPC", value = tostring(var.prefer_rest_over_grpc) },

      { name = "BENCHMARK_AUTODEPLOYPROCESS", value = tostring(var.auto_deploy_process) },
      { name = "BENCHMARK_STARTPROCESSES", value = "true" },
      { name = "BENCHMARK_STARTPIPERSECOND", value = tostring(var.start_rate) },
      { name = "BENCHMARK_STARTRATEADJUSTMENTSTRATEGY", value = var.rate_adjustment_strategy },
      { name = "BENCHMARK_WARMUPPHASEDURATIONMILLIS", value = tostring(var.warmup_phase_duration_millis) },

      { name = "BENCHMARK_STARTWORKERS", value = tostring(var.start_workers) },
      { name = "BENCHMARK_JOBTYPE", value = var.job_type },
      { name = "BENCHMARK_MULTIPLEJOBTYPES", value = tostring(var.multiple_job_types) },
      { name = "BENCHMARK_TASKCOMPLETIONDELAY", value = tostring(var.task_completion_delay) },

      { name = "JDK_JAVA_OPTIONS", value = "-XX:+HeapDumpOnOutOfMemoryError" },
      { name = "LOG_LEVEL", value = var.log_level },
    ],
    local.auth_environment,
    local.optional_environment,
    var.extra_environment_variables,
  )

  repository_credentials = var.registry_credentials_arn != "" ? {
    repositoryCredentials = {
      credentialsParameter = var.registry_credentials_arn
    }
  } : {}

  # The image bundles only multi-task processes, so the single-task workload the
  # absorbed benchmark drove is written into the container at startup and the
  # image's own entrypoint is then run. /tmp is writable for the image's
  # unprivileged user, which keeps this to one container and no volume.
  bpmn_path = "/tmp/one-task.bpmn"

  # The launcher is retried rather than exec'd. A failed initial deployment is
  # fatal to the image, and on a cold apply the Orchestration Cluster has no
  # Cloud Map record yet, so the first launch exits on "Unable to resolve host".
  # Exiting hands the problem to ECS, whose deployment circuit breaker stops
  # replacing the task after a few attempts and leaves a service with no
  # generator at all. The same loop covers the cluster going away later.
  container_command = join("", [
    "cat <<'BPMNEOF' > ${local.bpmn_path}\n",
    file("${path.module}/templates/one-task.bpmn"),
    "\nBPMNEOF\n",
    "until java org.springframework.boot.loader.launch.JarLauncher; do\n",
    "  echo 'load generator exited, retrying in 10s' >&2\n",
    "  sleep 10\n",
    "done",
  ])
}

resource "aws_ecs_task_definition" "load_generator" {
  family                   = "${var.prefix}-load-generator"
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  runtime_platform {
    operating_system_family = var.task_operating_system_family
    cpu_architecture        = var.task_cpu_architecture
  }

  lifecycle {
    precondition {
      condition     = var.auth_method != "basic" || var.auth_password_secret_arn != ""
      error_message = "auth_password_secret_arn must be set when auth_method is basic."
    }
  }

  container_definitions = jsonencode([
    merge({
      name        = "load-generator"
      image       = var.image
      essential   = true
      entryPoint  = ["/bin/sh", "-c"]
      command     = [local.container_command]
      environment = local.environment
      secrets     = local.auth_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "load-generator"
        }
      }
    }, local.repository_credentials),
  ])
}

resource "aws_ecs_service" "load_generator" {
  name            = "${var.prefix}-load-generator"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.load_generator.arn
  desired_count   = var.task_desired_count
  launch_type     = "FARGATE"

  enable_execute_command = var.task_enable_execute_command
  force_new_deployment   = var.service_force_new_deployment

  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  network_configuration {
    subnets          = var.vpc_private_subnets
    security_groups  = var.service_security_group_ids
    assign_public_ip = false
  }

  # The generator has no load balancer and no health endpoint, so a steady
  # state only means "the tasks started". Waiting for it is off by default to
  # keep an apply from blocking on a benchmark that is meant to run for hours.
  wait_for_steady_state = var.wait_for_steady_state

  timeouts {
    create = var.service_timeouts.create
    update = var.service_timeouts.update
    delete = var.service_timeouts.delete
  }
}
