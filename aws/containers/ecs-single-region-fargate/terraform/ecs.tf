locals {
  env_lines = split("\n", templatefile("${path.module}/templates/core-environment", {
    opensearch_url = "https://${join("", module.opensearch_domain[*].opensearch_domain_endpoint)}"
  }))
  env_kv_pairs = [
    for line in local.env_lines : {
      name  = trim(split("=", line)[0], " ")
      value = trim(join("=", slice(split("=", line), 1, length(split("=", line)))), " ")
    }
    if length(split("=", line)) > 1  # Filter out lines without '='
  ]
}

resource "aws_ecs_cluster" "ecs" {
  name = "${var.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "core" {
  count = var.camunda_count

  family                   = "${var.prefix}-core-${count.index}"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 2048
  memory                   = 4096
  container_definitions = templatefile("./templates/core.json.tpl", {
    core_image  = "registry.camunda.cloud/team-zeebe/camunda-ecs:8.9.0.${var.ecs-revision}"
    # core_image  = "registry.camunda.cloud/team-hto/camunda/camunda:ecs-lease-hack-v4"
    core_cpu    = 2048
    core_memory = 4096
    aws_region  = "eu-north-1"
    prefix      = var.prefix
    env_vars_json = jsonencode(concat([
      {
        name  = "ZEEBE_BROKER_CLUSTER_INITIALCONTACTPOINTS"
        value = join(",", [for i in range(var.camunda_count) : "${var.prefix}-ecs-${i}.${var.prefix}.service.local:26502"])
      },
      {
        name  = "ZEEBE_BROKER_CLUSTER_CLUSTERSIZE"
        value = "3"
      },
      {
        name  = "ZEEBE_BROKER_CLUSTER_REPLICATIONFACTOR"
        value = "3"
      },
      # {
      #   name  = "ZEEBE_BROKER_NETWORK_ADVERTISEDHOST"
      #   value = "0.0.0.0"
      #   # value = "${var.prefix}-ecs-${count.index}.${var.prefix}.service.local"
      # },
      {
        name  = "ZEEBE_BROKER_LEASECONFIG_SECRETKEY"
        value = aws_iam_access_key.s3_user_key.secret
      },
      {
        name  = "ZEEBE_BROKER_LEASECONFIG_BUCKETNAME"
        value = aws_s3_bucket.main.id
      },
      {
        name  = "ZEEBE_BROKER_LEASECONFIG_ACCESSKEY"
        value = aws_iam_access_key.s3_user_key.id
      }
    ], local.env_kv_pairs))
    docker_hub_credentials_arn = var.docker_hub_username != "" ? aws_secretsmanager_secret.docker_hub_credentials[0].arn : ""
  })

  task_role_arn = aws_iam_role.ecs_task_role.arn

  volume {
    name = "camunda-volume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs[count.index].id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.camunda_data[count.index].id
        iam             = "ENABLED"
      }
    }
  }

}
resource "aws_ecs_task_definition" "nginx-static" {
  count = var.camunda_count

  family                   = "${var.prefix}-nginx-static-family"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  container_definitions = templatefile("./templates/nginx.json.tpl", {
    core_image  = "registry.camunda.cloud/team-zeebe/nginx-static:latest"
    # core_image  = "registry.camunda.cloud/team-hto/camunda/camunda:ecs-lease-hack-v4"
    core_cpu    = 256
    core_memory = 512
    aws_region  = "eu-north-1"
    prefix      = var.prefix
    env_vars_json = jsonencode([
      {
        name  = "SERVER_PORT"
        value = "4000"
      },
      {
        name  = "AUTH_USER"
        value = "camunda" 
      },
      {
        name  = "AUTH_PASS"
        value = var.nginx_pass 
      }]),
    docker_hub_credentials_arn = var.docker_hub_username != "" ? aws_secretsmanager_secret.docker_hub_credentials[0].arn : ""
  })

  task_role_arn = aws_iam_role.ecs_task_role.arn

  volume {
    name = "camunda-volume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.efs[count.index].id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.camunda_data[count.index].id
        iam             = "ENABLED"
      }
    }
  }

}

resource "aws_ecs_service" "nginx" {
  count = var.camunda_count

  name                              = "${var.prefix}-nginx-service-${count.index}"
  cluster                           = aws_ecs_cluster.ecs.id
  task_definition                   = aws_ecs_task_definition.nginx-static[count.index].arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  force_new_deployment = true

  # Enable execute command for debugging
  enable_execute_command = true

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  network_configuration {
    subnets = module.vpc.private_subnets
    security_groups = [
      aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
      aws_security_group.allow_package_80_443.id,
      aws_security_group.allow_remote_4000.id,
      aws_security_group.efs.id,
    ]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.nginx.arn
  }

  # We register all services to same target group, this will then do the load balancing for our services
  load_balancer {
    target_group_arn = aws_lb_target_group.nginx_4000[0].arn
    container_name   = "${var.prefix}-nginx-static"
    container_port   = 4000
  }

}
resource "aws_ecs_service" "core" {
  count = var.camunda_count

  name                              = "${var.prefix}-core-service-${count.index}"
  cluster                           = aws_ecs_cluster.ecs.id
  task_definition                   = aws_ecs_task_definition.core[count.index].arn
  desired_count                     = 0
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 300
  force_new_deployment = true

  # Enable execute command for debugging
  enable_execute_command = true

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 67

  network_configuration {
    subnets = module.vpc.private_subnets
    security_groups = [
      aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
      aws_security_group.allow_package_80_443.id,
      aws_security_group.efs.id,
    ]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.discovery[count.index].arn
  }

  # We register all services to same target group, this will then do the load balancing for our services
  load_balancer {
    target_group_arn = aws_lb_target_group.main[0].arn
    container_name   = "${var.prefix}-core"
    container_port   = 8080
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_9600[0].arn
    container_name   = "${var.prefix}-core"
    container_port   = 9600
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_26500[0].arn
    container_name   = "${var.prefix}-core"
    container_port   = 26500
  }
}



# Starter task definition (Zeebe client load generator)
# resource "aws_ecs_task_definition" "starter" {
#   family                   = "${var.prefix}-starter"
#   execution_role_arn       = aws_iam_role.ecs_task_execution.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn
#   network_mode             = "awsvpc"
#   depends_on = [aws_ecs_service.core  ]
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = 256
#   memory                   = 512
#
#   container_definitions = jsonencode([
#     {
#       name      = "starter"
#       image = "registry.camunda.cloud/team-zeebe/starter:SNAPSHOT"
#       essential = true
#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           awslogs-group         = aws_cloudwatch_log_group.starter_log_group.name
#           awslogs-region        = data.aws_region.current.name
#           awslogs-stream-prefix = "starter"
#         }
#       }
#       repositoryCredentials: {
#         credentialsParameter: aws_secretsmanager_secret.docker_hub_credentials[0].arn
#       },
#       environment = [
#         { name = "JDK_JAVA_OPTIONS", value = "-Dconfig.override_with_env_vars=true -Dapp.brokerUrl=grpc://${var.prefix}-ecs-0.${var.prefix}.service.local:26500 -Dapp.brokerRestUrl=http://${var.prefix}-core-service-0.${var.prefix}.service.local:8080 -Dapp.preferRest=false -Dapp.starter.rate=100 -Dapp.starter.durationLimit=0 -Dzeebe.client.requestTimeout=62000 -Dapp.starter.processId=benchmark -Dapp.starter.bpmnXmlPath=bpmn/one_task.bpmn -Dapp.starter.businessKey=businessKey -Dapp.starter.payloadPath=bpmn/typical_payload.json -XX:+HeapDumpOnOutOfMemoryError" },
#         { name = "LOG_LEVEL", value = "WARN" }
#       ]
#       portMappings = [
#         { containerPort = 9600, hostPort = 9600, protocol = "tcp" }
#       ],
#
#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           awslogs-group         = aws_cloudwatch_log_group.prometheus_log_group.name
#           awslogs-region        = data.aws_region.current.name
#           awslogs-stream-prefix = "starter"
#         }
#       }
#     }
#   ])
# }
#
# # Starter service (no public exposure, single task)
# resource "aws_ecs_service" "starter" {
#   name            = "${var.prefix}-starter-service"
#   cluster         = aws_ecs_cluster.ecs.id
#   task_definition = aws_ecs_task_definition.starter.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"
#   enable_execute_command = true
#
#   network_configuration {
#     subnets         = module.vpc.private_subnets
#     security_groups = [
#       aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
#       aws_security_group.allow_package_80_443.id,
#     ]
#     assign_public_ip = false
#   }
# }
#
#
# # Worker task definition (Zeebe job worker)
# resource "aws_ecs_task_definition" "worker" {
#   family                   = "${var.prefix}-worker"
#   execution_role_arn       = aws_iam_role.ecs_task_execution.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn
#   network_mode             = "awsvpc"
#   depends_on = [aws_ecs_service.core  ]
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = 256 
#   memory                   = 512
#
#   container_definitions = jsonencode([
#     {
#       name      = "worker"
#       image = "registry.camunda.cloud/team-zeebe/worker:SNAPSHOT"
#       repositoryCredentials: {
#         credentialsParameter: aws_secretsmanager_secret.docker_hub_credentials[0].arn
#       },
#       essential = true
#       environment = [
#         { name = "JDK_JAVA_OPTIONS", value = "-Dconfig.override_with_env_vars=true -Dapp.brokerUrl=grpc://${var.prefix}-ecs-0.${var.prefix}.service.local:26500 -Dapp.brokerRestUrl=http://${var.prefix}-core-service-0.${var.prefix}.service.local:8080 -Dapp.preferRest=false -Dzeebe.client.requestTimeout=62000 -Dapp.worker.capacity=60 -Dapp.worker.threads=10 -Dapp.worker.pollingDelay=1ms -Dapp.worker.completionDelay=50ms -Dapp.worker.workerName=worker -Dapp.worker.jobType=benchmark-task -Dapp.worker.payloadPath=bpmn/typical_payload.json -XX:+HeapDumpOnOutOfMemoryError" },
#         { name = "LOG_LEVEL", value = "WARN" }
#       ]
#       portMappings = [
#         { containerPort = 9600, hostPort = 9600, protocol = "tcp" }
#       ],
#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           awslogs-group         = aws_cloudwatch_log_group.prometheus_log_group.name
#           awslogs-region        = data.aws_region.current.name
#           awslogs-stream-prefix = "worker"
#         }
#       }
#     }
#   ])
# }
#
# # Worker service (internal only, 3 replicas)
# resource "aws_ecs_service" "worker" {
#   name            = "${var.prefix}-worker-service"
#   cluster         = aws_ecs_cluster.ecs.id
#   task_definition = aws_ecs_task_definition.worker.arn
#   desired_count   = 3
#   launch_type     = "FARGATE"
#   enable_execute_command = true
#
#   network_configuration {
#     subnets         = module.vpc.private_subnets
#     security_groups = [
#       aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
#       aws_security_group.allow_package_80_443.id,
#     ]
#     assign_public_ip = false
#   }
# }
#
# # Prometheus task definition
# resource "aws_ecs_task_definition" "prometheus" {
#   family                   = "${var.prefix}-prometheus"
#   execution_role_arn       = aws_iam_role.ecs_task_execution.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = 256
#   memory                   = 512
#
#   container_definitions = jsonencode([
#     {
#       name      = "prometheus"
#       image     = "prom/prometheus:latest"
#       essential = true
#       portMappings = [
#         { containerPort = 9090, hostPort = 9090, protocol = "tcp" }
#       ]
#       entryPoint = ["/bin/sh", "-c"]
#       command = [
#         "cat <<'EOF' >/etc/prometheus/prometheus.yml\n${templatefile("${path.module}/templates/prometheus-config.yml.tpl", { prefix = var.prefix, names = join("\n", [for i in range(var.camunda_count) : "        - ${var.prefix}-ecs-${i}.${var.prefix}.service.local"]) }) }\nEOF\nexec /bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.retention.time=6h --web.enable-lifecycle"
#       ]
#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           awslogs-group         = aws_cloudwatch_log_group.prometheus_log_group.name
#           awslogs-region        = data.aws_region.current.name
#           awslogs-stream-prefix = "prometheus"
#         }
#       }
#     }
#   ])
# }
#
# # Prometheus service (internal only)
# resource "aws_ecs_service" "prometheus" {
#   depends_on = [aws_lb_target_group.prometheus_9090]
#   name            = "${var.prefix}-prometheus"
#   cluster         = aws_ecs_cluster.ecs.id
#   task_definition = aws_ecs_task_definition.prometheus.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"
#   enable_execute_command = true
#
#   network_configuration {
#     subnets         = module.vpc.private_subnets
#     security_groups = [
#       aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
#       aws_security_group.allow_package_80_443.id,
#     ]
#     assign_public_ip = false
#   }
#
#   service_registries {
#     registry_arn = aws_service_discovery_service.prometheus.arn
#   }
#
#   load_balancer {
#     target_group_arn = aws_lb_target_group.prometheus_9090[0].arn
#     container_name   = "prometheus"
#     container_port   = 9090
#   }
# }
#
# # Grafana task definition
# resource "aws_ecs_task_definition" "grafana" {
#   family                   = "${var.prefix}-grafana"
#   execution_role_arn       = aws_iam_role.ecs_task_execution.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = 512
#   memory                   = 1024
#
#   container_definitions = jsonencode([
#     {
#       name      = "grafana"
#       image     = "grafana/grafana:latest"
#       essential = true
#       portMappings = [
#         { containerPort = 3000, hostPort = 3000, protocol = "tcp" }
#       ]
#       environment = [
#         { name = "GF_SECURITY_ADMIN_USER", value = vars.grafana_user },
#         { name = "GF_SECURITY_ADMIN_PASSWORD", value = vars.grafana_pass },
#         { name = "GF_INSTALL_PLUGINS", value = "grafana-piechart-panel" },
#         { name = "GF_FEATURE_TOGGLES_ENABLE", value = "publicDashboards" }
#       ]
#       entryPoint = ["/bin/sh", "-c"]
#       command = ["cat <<'EOF' >/etc/grafana/provisioning/datasources/prometheus.yml\napiVersion: 1\ndatasources:\n  - name: Prometheus\n    type: prometheus\n    url: http://prometheus.${var.prefix}.service.local:9090\n    access: proxy\n    isDefault: true\n    editable: true\n    jsonData:\n      httpMethod: GET\nEOF\nmkdir -p /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards && cat <<'YAML' >/etc/grafana/provisioning/dashboards/zeebe.yaml\napiVersion: 1\nproviders:\n  - name: 'zeebe'\n    orgId: 1\n    folder: ''\n    type: file\n    disableDeletion: true\n    editable: false\n    options:\n      path: /var/lib/grafana/dashboards\nYAML\ncurl -Ls https://raw.githubusercontent.com/camunda/camunda/main/monitor/grafana/zeebe.json -o /var/lib/grafana/dashboards/zeebe.json || echo 'failed to fetch dashboard';\nexec /run.sh"]
#       # CloudWatch logging disabled per request
#     }
#   ])
# }
#
# # Grafana service (exposed via ALB 3000)
# resource "aws_ecs_service" "grafana" {
#   depends_on = [aws_ecs_service.prometheus]
#   name            = "${var.prefix}-grafana-service"
#   cluster         = aws_ecs_cluster.ecs.id
#   task_definition = aws_ecs_task_definition.grafana.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"
#   enable_execute_command = true
#
#   network_configuration {
#     subnets         = module.vpc.private_subnets
#     security_groups = [
#       aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
#       aws_security_group.allow_package_80_443.id,
#     ]
#     assign_public_ip = false
#   }
#
#   load_balancer {
#     target_group_arn = aws_lb_target_group.grafana_3000[0].arn
#     container_name   = "grafana"
#     container_port   = 3000
#   }
# }
#
#
