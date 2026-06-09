################################################################
#           Load Balancers - Region 0                          #
################################################################

# ALB for HTTP/REST (region 0)
resource "aws_lb" "alb_region_0" {
  name               = "${local.prefix_truncated}-r0-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.camunda_ports_region_0.id,
    aws_security_group.remote_access_region_0.id,
  ]
  subnets = local.vpc.region_0_public_subnet_ids
}

resource "aws_lb_listener" "http_webapp_region_0" {
  load_balancer_arn = aws_lb.alb_region_0.arn
  port              = "80"
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

resource "aws_lb_listener" "http_management_region_0" {
  load_balancer_arn = aws_lb.alb_region_0.arn
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

# External NLB for gRPC (region 0)
resource "aws_lb" "nlb_grpc_region_0" {
  name               = "${local.prefix_truncated}-r0-nlb-grpc"
  internal           = false
  load_balancer_type = "network"
  security_groups = [
    aws_security_group.camunda_ports_region_0.id,
    aws_security_group.remote_access_region_0.id,
  ]
  subnets = local.vpc.region_0_public_subnet_ids
}

# Internal NLB for cross-region Raft (region 0)
resource "aws_lb" "nlb_raft_region_0" {
  name               = "${local.prefix_truncated}-r0-nlb-raft"
  internal           = true
  load_balancer_type = "network"
  security_groups = [
    aws_security_group.camunda_ports_region_0.id,
  ]
  subnets = local.vpc.region_0_private_subnet_ids
}

################################################################
#           Load Balancers - Region 1                          #
################################################################

# ALB for HTTP/REST (region 1)
resource "aws_lb" "alb_region_1" {
  provider = aws.accepter

  name               = "${local.prefix_truncated}-r1-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.camunda_ports_region_1.id,
    aws_security_group.remote_access_region_1.id,
  ]
  subnets = local.vpc.region_1_public_subnet_ids
}

resource "aws_lb_listener" "http_webapp_region_1" {
  provider = aws.accepter

  load_balancer_arn = aws_lb.alb_region_1.arn
  port              = "80"
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

resource "aws_lb_listener" "http_management_region_1" {
  provider = aws.accepter

  load_balancer_arn = aws_lb.alb_region_1.arn
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

# External NLB for gRPC (region 1)
resource "aws_lb" "nlb_grpc_region_1" {
  provider = aws.accepter

  name               = "${local.prefix_truncated}-r1-nlb-grpc"
  internal           = false
  load_balancer_type = "network"
  security_groups = [
    aws_security_group.camunda_ports_region_1.id,
    aws_security_group.remote_access_region_1.id,
  ]
  subnets = local.vpc.region_1_public_subnet_ids
}

# Internal NLB for cross-region Raft (region 1)
resource "aws_lb" "nlb_raft_region_1" {
  provider = aws.accepter

  name               = "${local.prefix_truncated}-r1-nlb-raft"
  internal           = true
  load_balancer_type = "network"
  security_groups = [
    aws_security_group.camunda_ports_region_1.id,
  ]
  subnets = local.vpc.region_1_private_subnet_ids
}
