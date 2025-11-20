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
