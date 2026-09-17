locals {
  targets_file = "/etc/prometheus/targets/targets.json"

  log_group_name = var.log_group_name != "" ? var.log_group_name : aws_cloudwatch_log_group.monitoring[0].name

  # Both containers are fed their config through a heredoc in the entrypoint
  # rather than a baked image or a mounted volume. It keeps the module to stock
  # upstream images, which is what lets anyone copying this reference pull them.
  discovery_command = "cat <<'SCRIPT' > /tmp/discover.sh\n${file("${path.module}/templates/discover-targets.sh")}\nSCRIPT\nchmod +x /tmp/discover.sh && exec /tmp/discover.sh"

  prometheus_config = templatefile("${path.module}/templates/prometheus-config.yml.tpl", {
    prefix           = var.prefix
    scrape_interval  = var.scrape_interval
    metrics_path     = var.metrics_path
    targets_file     = local.targets_file
    refresh_interval = var.discovery_refresh_interval_seconds
  })

  prometheus_command = join("", [
    "cat <<'EOF' >/etc/prometheus/prometheus.yml\n",
    local.prometheus_config,
    "\nEOF\n",
    "exec /bin/prometheus",
    " --config.file=/etc/prometheus/prometheus.yml",
    " --storage.tsdb.retention.time=${var.retention_time}",
    " --web.enable-lifecycle",
    " --web.listen-address=:${var.prometheus_port}",
  ])

  repository_credentials = var.registry_credentials_arn != "" ? {
    repositoryCredentials = {
      credentialsParameter = var.registry_credentials_arn
    }
  } : {}
}

resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.prefix}-prometheus"
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

  container_definitions = jsonencode([
    merge({
      name       = "discovery"
      image      = var.discovery_image
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.discovery_command]
      environment = [
        { name = "TARGETS_FILE", value = local.targets_file },
        { name = "REFRESH_INTERVAL", value = tostring(var.discovery_refresh_interval_seconds) },
        { name = "PORT", value = tostring(var.metrics_port) },
        { name = "METRICS_PATH", value = var.metrics_path },
        { name = "NAMESPACE_SUFFIX", value = var.discovery_namespace_suffix },
        { name = "SERVICE_NAME", value = var.discovery_service_name },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
      ]
      mountPoints = [
        {
          sourceVolume  = "targets"
          containerPath = "/etc/prometheus/targets"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "discovery"
        }
      }
    }, local.repository_credentials),

    merge({
      name      = "prometheus"
      image     = var.image
      essential = true
      # START, not HEALTHY: the sidecar is a loop with no completion state, and
      # Prometheus tolerates an empty target file, so waiting any longer would
      # only delay the server for nothing.
      dependsOn = [
        { containerName = "discovery", condition = "START" }
      ]
      portMappings = [
        { containerPort = var.prometheus_port, hostPort = var.prometheus_port, protocol = "tcp" }
      ]
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.prometheus_command]
      mountPoints = [
        {
          sourceVolume  = "targets"
          containerPath = "/etc/prometheus/targets"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "prometheus"
        }
      }
    }, local.repository_credentials),
  ])

  volume {
    name = "targets"
  }
}

resource "aws_ecs_service" "prometheus" {
  name            = "${var.prefix}-prometheus"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = var.task_enable_execute_command
  force_new_deployment   = var.service_force_new_deployment

  # Storage is the task's own ephemeral volume, so two replicas would hold two
  # unrelated halves of the history. One task at a time, replaced rather than
  # doubled.
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  network_configuration {
    subnets          = var.vpc_private_subnets
    security_groups  = var.service_security_group_ids
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.prometheus.arn
  }

  dynamic "load_balancer" {
    for_each = var.enable_alb_http_listener_rule ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.prometheus[0].arn
      container_name   = "prometheus"
      container_port   = var.prometheus_port
    }
  }

  wait_for_steady_state = var.wait_for_steady_state

  timeouts {
    create = var.service_timeouts.create
    update = var.service_timeouts.update
    delete = var.service_timeouts.delete
  }
}
