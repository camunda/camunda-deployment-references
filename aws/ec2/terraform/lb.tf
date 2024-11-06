################################################################
#             Application Load Balancer (WebApps)              #
################################################################

# Create a target group for the ALB - targeting port 8080
# Operate / Tasklist WebApps
resource "aws_lb_target_group" "main" {
  name     = "${var.prefix}-tg-8080"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
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

# Attach the instances to the target group, scales automatically based on the number of instances
resource "aws_lb_target_group_attachment" "main" {
  depends_on       = [aws_instance.camunda]
  for_each         = { for idx, instance in aws_instance.camunda : idx => instance }
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = each.value.id
  port             = 8080
}

# Attach the instances to the target group, scales automatically based on the number of instances
resource "aws_lb_target_group_attachment" "connectors" {
  depends_on       = [aws_instance.camunda]
  for_each         = { for idx, instance in aws_instance.camunda : idx => instance }
  target_group_arn = aws_lb_target_group.connectors.arn
  target_id        = each.value.id
  port             = 9090
}

# Connectors
resource "aws_lb_target_group" "connectors" {
  name     = "${var.prefix}-tg-9090"
  port     = 9090
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/actuator/health/"
    port                = "9090"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Application Load Balancer to expose the WebApps
resource "aws_lb" "main" {
  count = var.enable_alb ? 1 : 0

  name               = "${var.prefix}-alb-webui"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.allow_remote_80_443.id,
    aws_security_group.allow_remote_9090.id,
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
  ]
  subnets = module.vpc.public_subnets
}

resource "aws_lb_listener" "http_8080" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_lb_listener" "http_9090" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = "9090"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.connectors.arn
  }
}

################################################################
#            Network Load Balancer (gRPC endpoint)             #
################################################################

resource "aws_lb_target_group" "grpc" {
  name     = "${var.prefix}-tg-grpc"
  port     = 26500
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    port                = "26500"
    protocol            = "TCP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "grpc" {
  depends_on       = [aws_instance.camunda]
  for_each         = { for idx, instance in aws_instance.camunda : idx => instance }
  target_group_arn = aws_lb_target_group.grpc.arn
  target_id        = each.value.id
  port             = 26500
}

resource "aws_lb" "grpc" {
  count = var.enable_nlb ? 1 : 0

  name               = "${var.prefix}-nlb-grpc"
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

  load_balancer_arn = aws_lb.grpc[0].arn
  port              = "26500"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grpc.arn
  }
}
