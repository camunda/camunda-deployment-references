################################################################
#                      WebApps                                 #
################################################################

# resource "aws_lb_target_group" "main" {
#   name        = "${var.prefix}-tg-8080"
#   port        = 8080
#   protocol    = "HTTP"
#   vpc_id      = var.vpc_id
#   target_type = "ip"

#   # Faster deregistration for quicker deployments
#   deregistration_delay = 30

#   health_check {
#     path                = "/actuator/health"
#     port                = "9600"
#     protocol            = "HTTP"
#     timeout             = 5
#     interval            = 30
#     healthy_threshold   = 2
#     unhealthy_threshold = 2
#   }

#   # Stickiness for 12 hours
#   stickiness {
#     enabled         = true
#     type            = "lb_cookie"
#     cookie_duration = 43200
#   }
# }

# TODO: disable, purely for testing purposes
resource "aws_lb_target_group" "main_9600" {
  name        = "${var.prefix}-tg-9600"
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
# resource "aws_lb_listener" "http_8080" {
#   load_balancer_arn = var.alb_arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.main.arn
#   }
# }

# core management api
resource "aws_lb_listener" "http_9600" {
  load_balancer_arn = var.alb_arn
  port              = "9600"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_9600.arn
  }
}


################################################################
#                      gRPC                                    #
################################################################

resource "aws_lb_target_group" "main_26500" {
  name        = "${var.prefix}-tg-26500"
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
  load_balancer_arn = var.nlb_arn
  port              = "26500"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_26500.arn
  }
}
