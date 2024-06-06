# Create a target group for the ALB - targeting port 8080
# Operate / Tasklist WebApps
resource "aws_lb_target_group" "main" {
  name     = "${var.prefix}-tg-8080"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
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

# Attach the instances to the target group, scales automatically based on the number of instances
resource "aws_lb_target_group_attachment" "main" {
  depends_on       = [aws_instance.camunda]
  for_each         = { for idx, instance in aws_instance.camunda : idx => instance }
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = each.value.id
  port             = 8080
}

resource "aws_lb" "main" {
  count = var.enable_alb ? 1 : 0

  name               = "${var.prefix}-alb-8080"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.allow_remote_80_443.id,
    aws_security_group.allow_any_traffic_within_vpc.id,
  ]
  subnets = module.vpc.public_subnets
}

resource "aws_lb_listener" "http_8080" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
