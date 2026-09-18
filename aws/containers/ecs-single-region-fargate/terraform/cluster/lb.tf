resource "aws_lb" "main" {
  name               = "${var.prefix}-alb-webui"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_remote_80_443.id,
    aws_security_group.allow_remote_9600.id,
  ]
  subnets = module.vpc.public_subnets
}

resource "aws_lb_listener" "http_webapp" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80" # Plain HTTP for the demo. Provide var.alb_certificate_arn to serve over HTTPS :443 instead.
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = ""
      status_code  = "200"
    }
  }
}

locals {
  # TLS is opt-in via an ACM certificate. When provided, web-app/OIDC traffic is
  # served over HTTPS :443 and the component modules attach their path rules to
  # that listener; HTTP :80 then only redirects to it. Empty (the demo default) →
  # everything below is count-gated off and traffic stays on plain HTTP :80.
  alb_https_enabled   = var.alb_certificate_arn != ""
  webapp_listener_arn = local.alb_https_enabled ? aws_lb_listener.https_webapp[0].arn : aws_lb_listener.http_webapp.arn
}

# HTTPS web-app/OIDC listener — prepared for TLS, created only when an ACM
# certificate is supplied (not used in the demo). Component modules attach their
# path rules to local.webapp_listener_arn, so they follow this listener when TLS
# is enabled with no per-module changes. Behind it, Keycloak receives
# X-Forwarded-Proto=https (KC_PROXY_HEADERS), so the realm's default
# sslRequired=external is satisfied with no manual relaxation.
resource "aws_lb_listener" "https_webapp" {
  count = local.alb_https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = var.alb_ssl_policy
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = ""
      status_code  = "200"
    }
  }
}

# Redirect plain HTTP to HTTPS when TLS is enabled (component rules live on :443).
resource "aws_lb_listener_rule" "http_to_https_redirect" {
  count = local.alb_https_enabled ? 1 : 0

  listener_arn = aws_lb_listener.http_webapp.arn
  priority     = 1

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

resource "aws_lb_listener" "http_management" {
  load_balancer_arn = aws_lb.main.arn
  port              = "9600"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = ""
      status_code  = "200"
    }
  }
}

resource "aws_lb" "grpc" {
  name               = "${var.prefix}-nlb-grpc"
  internal           = false
  load_balancer_type = "network"
  security_groups = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_remote_grpc.id,
  ]

  subnets = module.vpc.public_subnets
}
