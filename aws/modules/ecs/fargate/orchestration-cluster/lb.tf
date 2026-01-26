################################################################
#                      WebApps                                 #
################################################################

resource "aws_lb_target_group" "main" {
  # target groups are limited to 32 characters, truncating to less to not clash
  name        = "${substr(var.prefix, 0, 17)}-orc-tg-8080"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
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

  # Stickiness for 12 hours
  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 43200
  }
}

resource "aws_lb_target_group" "main_9600" {
  # target groups are limited to 32 characters, truncating to less to not clash
  name        = "${substr(var.prefix, 0, 17)}-orc-tg-9600"
  port        = 9600
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
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

# core webapp + rest api
# We create a listener rule to reuse the same Load Balancer Listener Port 80 to expose the applications via a path-based routing
resource "aws_lb_listener_rule" "http_webapp" {
  count = var.enable_alb_http_webapp_listener_rule ? 1 : 0

  listener_arn = var.alb_listener_http_webapp_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

}

# management port - not recommended to be exposed publicly
resource "aws_lb_listener_rule" "http_management" {
  count = var.enable_alb_http_management_listener_rule ? 1 : 0

  listener_arn = var.alb_listener_http_management_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_9600.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

}

################################################################
#                      gRPC                                    #
################################################################

resource "aws_lb_target_group" "main_26500" {
  # target groups are limited to 32 characters, truncating to less to not clash
  name        = "${substr(var.prefix, 0, 17)}-orc-tg-26500"
  port        = 26500
  protocol    = "TCP"
  vpc_id      = var.vpc_id
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

resource "aws_lb_listener" "grpc_26500" {
  count = var.enable_nlb_grpc_26500_listener ? 1 : 0

  load_balancer_arn = var.nlb_arn
  port              = "26500"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_26500.arn
  }
}
