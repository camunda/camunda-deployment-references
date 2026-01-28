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
  port              = "80" # We use port 80 as example, feel free to change to 443 with proper SSL certs and domain
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
