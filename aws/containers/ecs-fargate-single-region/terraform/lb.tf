################################################################
#             Application Load Balancer (WebApps)              #
################################################################

# Create a target group for the ALB - targeting port 8080
# Operate / Tasklist WebApps
resource "aws_lb_target_group" "main" {
  name        = "${var.prefix}-tg-8080"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

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
  name        = "${var.prefix}-tg-9600"
  port        = 9600
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

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

resource "aws_lb_target_group" "main_9090" {
  name        = "${var.prefix}-tg-9090"
  port        = 9090
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/actuator/health"
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
    aws_security_group.allow_remote_9600.id
  ]
  subnets = module.vpc.public_subnets
}

# core webapp + rest api
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

# core management api
resource "aws_lb_listener" "http_9600" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = "9600"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_9600.arn
  }
}

# connectors
resource "aws_lb_listener" "http_9090" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = "9090"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_9090.arn
  }
}
