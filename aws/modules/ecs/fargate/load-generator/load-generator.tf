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
    var.bpmn_process_id != "" ? [{ name = "BENCHMARK_BPMN_PROCESS_ID", value = var.bpmn_process_id }] : [],
    var.bpmn_resource != "" ? [{ name = "BENCHMARK_BPMN_RESOURCE", value = var.bpmn_resource }] : [],
  )

  environment = concat(
    [
      { name = "CAMUNDA_CLIENT_MODE", value = "self-managed" },
      { name = "CAMUNDA_CLIENT_ZEEBE_GRPC_ADDRESS", value = local.grpc_address },
      { name = "CAMUNDA_CLIENT_ZEEBE_REST_ADDRESS", value = local.rest_address },
      { name = "CAMUNDA_CLIENT_ZEEBE_PREFER_REST_OVER_GRPC", value = tostring(var.prefer_rest_over_grpc) },

      { name = "BENCHMARK_AUTO_DEPLOY_PROCESS", value = tostring(var.auto_deploy_process) },
      { name = "BENCHMARK_START_PROCESSES", value = "true" },
      { name = "BENCHMARK_START_PI_PER_SECOND", value = tostring(var.start_rate) },
      { name = "BENCHMARK_START_RATE_ADJUSTMENT_STRATEGY", value = var.rate_adjustment_strategy },
      { name = "BENCHMARK_WARMUP_PHASE_DURATION_MILLIS", value = tostring(var.warmup_phase_duration_millis) },

      { name = "BENCHMARK_START_WORKERS", value = tostring(var.start_workers) },
      { name = "BENCHMARK_JOBTYPE", value = var.job_type },
      { name = "BENCHMARK_MULTIPLEJOBTYPES", value = tostring(var.multiple_job_types) },
      { name = "BENCHMARK_TASK_COMPLETION_DELAY", value = tostring(var.task_completion_delay) },

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
