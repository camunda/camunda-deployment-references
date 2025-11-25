resource "aws_lb_target_group" "main" {
  name        = "${var.prefix}-connectors-tg-8080"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # Faster deregistration for quicker deployments
  deregistration_delay = 30

  health_check {
    path                = "/actuator/health"
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
resource "aws_lb_listener_rule" "http_80" {
  listener_arn = var.alb_listener_http_80_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    path_pattern {
      values = ["/connectors/*"]
    }
  }

}
