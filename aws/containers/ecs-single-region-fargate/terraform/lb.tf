################################################################
#             Application Load Balancer (WebApps)              #
################################################################

# Create a target group for the ALB - targeting port 8080
# Operate / Tasklist WebApps
resource "aws_lb_target_group" "main" {
  count = var.camunda_count

  name        = "${var.prefix}-tg-8080-${count.index}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  # Faster deregistration for quicker deployments
  deregistration_delay = 30

  health_check {
    path                = "/operate"
    port                = "8080"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  # Stickiness for 12 hours
  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 43200
  }
}

resource "aws_lb_target_group" "main_9600" {
  count = var.camunda_count

  name        = "${var.prefix}-tg-9600-${count.index}"
  port        = 9600
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  # Faster deregistration for quicker deployments
  deregistration_delay = 30

  health_check {
    path                = "/actuator/health"
    port                = "9600"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "main_26500" {
  count = var.camunda_count

  name        = "${var.prefix}-tg-26500-${count.index}"
  port        = 26500
  protocol    = "TCP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  # Faster deregistration for quicker deployments
  deregistration_delay = 30

  health_check {
    path                = "/actuator/health"
    port                = "9600"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Application Load Balancer to expose the WebApps
resource "aws_lb" "main" {
  count = var.camunda_count

  name               = "${var.prefix}-alb-webui-${count.index}"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.allow_remote_80_443.id,
    aws_security_group.allow_remote_9090.id,
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_remote_9600.id
  ]
  subnets = module.vpc.public_subnets
}

# core webapp + rest api
resource "aws_lb_listener" "http_8080" {
  count = var.camunda_count

  load_balancer_arn = aws_lb.main[count.index].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[count.index].arn
  }
}

# core management api
resource "aws_lb_listener" "http_9600" {
  count = var.camunda_count

  load_balancer_arn = aws_lb.main[count.index].arn
  port              = "9600"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_9600[count.index].arn
  }
}

# gRPC

resource "aws_lb" "grpc" {
  count = var.camunda_count

  name               = "${var.prefix}-nlb-grpc-${count.index}"
  internal           = false
  load_balancer_type = "network"
  security_groups = [
    aws_security_group.allow_remote_grpc.id,
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
  ]

  subnets = module.vpc.public_subnets
}

resource "aws_lb_listener" "grpc_26500" {
  count = var.enable_nlb ? 1 : 0

  load_balancer_arn = aws_lb.grpc[count.index].arn
  port              = "26500"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_26500[count.index].arn
  }
}
