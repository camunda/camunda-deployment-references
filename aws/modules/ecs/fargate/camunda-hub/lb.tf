resource "aws_lb_target_group" "restapi" {
  # Target group names are limited to 32 characters.
  name        = "${substr(var.prefix, 0, 15)}-hub-tg-8081"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    # restapi serves health on the Spring Boot management port (8091), not the traffic port.
    path                = local.restapi_health_path
    port                = "8091"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 43200
  }
}

resource "aws_lb_target_group" "websockets" {
  name        = "${substr(var.prefix, 0, 12)}-hub-ws-tg-8060"
  port        = 8060
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    path                = "/up"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 43200
  }
}

# Reuse the shared HTTP webapp listener (port 80) with path-based routing.
# The websocket rule ("${context_path}-ws*") MUST have a lower priority number
# (evaluated first) than the restapi rule ("${context_path}*"), because a
# "/hub-ws/..." request matches both patterns; if the broader "/hub*" rule won,
# websocket traffic would be misrouted to the restapi container.
# Priorities 60/61 sit in a free band on the shared listener (siblings use
# 30 identity / 40 keycloak / 50 connectors / 100 orchestration catch-all).
resource "aws_lb_listener_rule" "hub" {
  count = var.enable_alb_http_webapp_listener_rule ? 1 : 0

  listener_arn = var.alb_listener_http_webapp_arn
  priority     = 61

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.restapi.arn
  }

  condition {
    path_pattern {
      values = ["${var.context_path}*"]
    }
  }
}

resource "aws_lb_listener_rule" "hub_ws" {
  count = var.enable_alb_http_webapp_listener_rule ? 1 : 0

  listener_arn = var.alb_listener_http_webapp_arn
  priority     = 60

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websockets.arn
  }

  condition {
    path_pattern {
      values = ["${var.context_path}-ws*"]
    }
  }
}
