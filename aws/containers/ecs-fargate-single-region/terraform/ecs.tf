resource "aws_ecs_cluster" "ecs" {
  name = "${var.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "core" {
  family                   = "${var.prefix}-core"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 2048
  memory                   = 4096
  container_definitions = templatefile("./templates/core.json.tpl", {
    core_image     = "camunda/camunda:SNAPSHOT"
    core_cpu       = 1536
    core_memory    = 3072
    aws_region     = "eu-north-1"
    prefix         = var.prefix
    opensearch_url = "https://${join("", module.opensearch_domain[*].opensearch_domain_endpoint)}"

    connectors_image  = "camunda/connectors:SNAPSHOT"
    connectors_cpu    = 512
    connectors_memory = 1024
  })

  volume {
    name                = "camunda-volume"
    configure_at_launch = "true"
  }


  depends_on = [module.opensearch_domain]
}

resource "aws_ecs_service" "core" {
  name            = "${var.prefix}-core-service"
  cluster         = aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.core.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  volume_configuration {
    name = "camunda-volume"
    managed_ebs_volume {
      role_arn         = aws_iam_role.ecs_service.arn
      volume_type      = "gp3"
      size_in_gb       = 50
      file_system_type = "ext4"
    }
  }

  network_configuration {
    subnets = module.vpc.private_subnets
    security_groups = [
      aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
      aws_security_group.allow_package_80_443.id,
    ]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "${var.prefix}-core"
    container_port   = 8080
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_9600.arn
    container_name   = "${var.prefix}-core"
    container_port   = 9600
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main_9090.arn
    container_name   = "${var.prefix}-connectors"
    container_port   = 9090
  }
}
