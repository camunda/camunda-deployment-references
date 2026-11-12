# Exposure stage: the load balancers in front of Camunda. It creates no routing rules:
# the components attach their own path rules to the listeners that this stage outputs.
# TLS is opt-in through an ACM certificate you provide; DNS records are yours to create
# (point alb_public_hostname at alb_dns_name).

locals {
  https_enabled        = var.alb_certificate_arn != ""
  webapp_listener_arn  = local.https_enabled ? aws_lb_listener.https_webapp[0].arn : aws_lb_listener.http_webapp.arn
  public_hostname      = var.alb_public_hostname != "" ? var.alb_public_hostname : aws_lb.main.dns_name
  public_base_url      = "${local.https_enabled ? "https" : "http"}://${local.public_hostname}"
  fixed_empty_response = { content_type = "text/plain", message_body = "", status_code = "200" }
}

resource "aws_lb" "main" {
  name               = "${var.prefix}-alb-webui"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    var.camunda_ports_security_group_id,
    aws_security_group.remote_80_443.id,
    aws_security_group.remote_9600.id,
  ]
  subnets = var.public_subnet_ids
}

resource "aws_lb_listener" "http_webapp" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = local.fixed_empty_response.content_type
      message_body = local.fixed_empty_response.message_body
      status_code  = local.fixed_empty_response.status_code
    }
  }
}

resource "aws_lb_listener" "https_webapp" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = var.alb_ssl_policy
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = local.fixed_empty_response.content_type
      message_body = local.fixed_empty_response.message_body
      status_code  = local.fixed_empty_response.status_code
    }
  }
}

# With TLS, component rules live on :443 and :80 only redirects.
resource "aws_lb_listener_rule" "http_to_https_redirect" {
  count = local.https_enabled ? 1 : 0

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
      content_type = local.fixed_empty_response.content_type
      message_body = local.fixed_empty_response.message_body
      status_code  = local.fixed_empty_response.status_code
    }
  }
}

resource "aws_lb" "grpc" {
  name               = "${var.prefix}-nlb-grpc"
  internal           = false
  load_balancer_type = "network"
  security_groups = [
    var.camunda_ports_security_group_id,
    aws_security_group.remote_grpc.id,
  ]
  subnets = var.public_subnet_ids
}

# Internal NLB on 26502, the traffic between brokers. Only needed once brokers in another
# region must reach this cluster: they use its DNS name as an initial contact point.
resource "aws_lb" "raft" {
  count = var.enable_raft_nlb ? 1 : 0

  name               = "${var.prefix}-nlb-raft"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [var.camunda_ports_security_group_id]
  subnets            = var.private_subnet_ids

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_ids) >= 3
      error_message = "enable_raft_nlb = true requires private_subnet_ids (at least 3)."
    }
  }
}
