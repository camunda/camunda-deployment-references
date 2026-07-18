# ALB target group + listener rule are opt-in (default off) for the MVP.
# Both are gated on enable_alb_http_webapp_listener_rule so that, when disabled,
# no load-balancer resources are created and the service runs Service-Connect-only.

resource "aws_lb_target_group" "main" {
  count = var.enable_alb_http_webapp_listener_rule ? 1 : 0

  # target groups are limited to 32 characters, truncating to less to not clash
  name        = "${substr(var.prefix, 0, 17)}-idty-tg-8084"
  port        = 8084
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # Faster deregistration for quicker deployments
  deregistration_delay = 30

  # Health check probes the management/actuator port (8082) liveness endpoint.
  health_check {
    path                = "/actuator/health/liveness"
    port                = "8082"
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

// Reuse the shared ALB listener via path-based routing. Priority 150 is unique
// vs orchestration (100) and connectors (50).
resource "aws_lb_listener_rule" "http_webapp" {
  count = var.enable_alb_http_webapp_listener_rule ? 1 : 0

  listener_arn = var.alb_listener_http_webapp_arn
  priority     = 150

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[0].arn
  }

  condition {
    path_pattern {
      values = ["/identity*"]
    }
  }
}
