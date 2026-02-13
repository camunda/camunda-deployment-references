resource "aws_lb_target_group" "main" {
  # target groups are limited to 32 characters, truncating to less to not clash
  name        = "${substr(var.prefix, 0, 17)}-con-tg-8080"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # Faster deregistration for quicker deployments
  deregistration_delay = 30

  health_check {
    path                = "/connectors/actuator/health/readiness"
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

// We create a listener rule to reuse the same Load Balancer Listener Port 80 to expose the applications via a path-based routing
resource "aws_lb_listener_rule" "http_webapp" {
  count = var.enable_alb_http_webapp_listener_rule ? 1 : 0

  listener_arn = var.alb_listener_http_webapp_arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    path_pattern {
      values = ["/connectors*"]
    }
  }

}
