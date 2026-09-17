# Prometheus serves an unauthenticated read of every metric it has scraped, so
# nothing here is created unless the consumer opts in by passing a listener.
# The default deployment is reachable only through the private DNS name.

resource "aws_lb_target_group" "prometheus" {
  count = var.enable_alb_http_listener_rule ? 1 : 0

  name        = substr("${var.prefix}-prom-tg", 0, 32)
  port        = var.prometheus_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/-/healthy"
    port                = tostring(var.prometheus_port)
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener_rule" "prometheus" {
  count = var.enable_alb_http_listener_rule ? 1 : 0

  listener_arn = var.alb_listener_http_arn
  priority     = var.alb_listener_rule_priority

  lifecycle {
    precondition {
      condition     = var.alb_listener_http_arn != ""
      error_message = "alb_listener_http_arn must be set when enable_alb_http_listener_rule is true."
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus[0].arn
  }

  condition {
    path_pattern {
      values = [var.alb_listener_rule_path_pattern]
    }
  }
}
