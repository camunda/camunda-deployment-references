################################################################
#                     Load test overlay                        #
################################################################

# The dual-region counterpart of the single-region overlay, absorbed from the
# dual-region load test in camunda/camunda-load-tests-ecs. It reuses the same
# two modules rather than a parallel stack:
#
# - one Prometheus per region, each discovering only its own region's brokers
#   through Cloud Map (the module filters namespaces by the hosted zone's VPC
#   association), so a region outage does not also blind the other side;
# - one load generator in region 0, the region that holds partition leadership
#   (ZONE_AWARE priority 1000, see locals.tf). Driving load from region 1 would
#   add a cross-region round trip to every command and measure the link, not
#   the engine.
#
# Off by default; with the flag off nothing below is planned, so the golden plan
# of this state is unchanged.
#
# Not carried over from the source repository: cross-region Prometheus
# federation and the Grafana side (dashboards are a separate decision), and the
# Lambda that periodically re-runs priority election to pull leadership back to
# region 0.

locals {
  load_tests_enabled = var.enable_load_tests ? 1 : 0
  load_tests_prefix  = "${local.infra.cluster_name}-lt"
}

data "aws_vpc" "region_0" {
  count = local.load_tests_enabled
  id    = local.infra.vpc_region_0_id
}

data "aws_vpc" "region_1" {
  count    = local.load_tests_enabled
  provider = aws.accepter
  id       = local.infra.vpc_region_1_id
}

# Prometheus listens on a port outside the cluster's own security groups, so
# enabling the overlay does not widen what the brokers accept.
resource "aws_security_group" "prometheus_region_0" {
  count = local.load_tests_enabled

  name        = "${local.load_tests_prefix}-r0-prometheus"
  description = "Allow access to the Prometheus UI and API from within the VPC"
  vpc_id      = local.infra.vpc_region_0_id

  ingress {
    from_port   = var.load_tests_prometheus_port
    to_port     = var.load_tests_prometheus_port
    protocol    = "TCP"
    cidr_blocks = [data.aws_vpc.region_0[0].cidr_block]
    description = "Prometheus UI and API, reachable inside the VPC only"
  }

  tags = {
    Name = "${local.load_tests_prefix}-r0-prometheus"
  }
}

resource "aws_security_group" "prometheus_region_1" {
  count    = local.load_tests_enabled
  provider = aws.accepter

  name        = "${local.load_tests_prefix}-r1-prometheus"
  description = "Allow access to the Prometheus UI and API from within the VPC"
  vpc_id      = local.infra.vpc_region_1_id

  ingress {
    from_port   = var.load_tests_prometheus_port
    to_port     = var.load_tests_prometheus_port
    protocol    = "TCP"
    cidr_blocks = [data.aws_vpc.region_1[0].cidr_block]
    description = "Prometheus UI and API, reachable inside the VPC only"
  }

  tags = {
    Name = "${local.load_tests_prefix}-r1-prometheus"
  }
}

module "monitoring_region_0" {
  count = local.load_tests_enabled

  source = "../../../../modules/ecs/fargate/monitoring"

  prefix              = "${local.load_tests_prefix}-r0"
  ecs_cluster_id      = local.infra.ecs_cluster_region_0_id
  vpc_id              = local.infra.vpc_region_0_id
  vpc_private_subnets = local.infra.vpc_region_0_private_subnets
  aws_region          = data.aws_region.region_0.region

  ecs_task_execution_role_arn = local.infra.ecs_task_execution_role_region_0_arn

  prometheus_port = var.load_tests_prometheus_port
  retention_time  = var.load_tests_retention_time

  service_security_group_ids = [
    local.infra.sg_camunda_ports_region_0_id,
    local.infra.sg_package_80_443_region_0_id,
    aws_security_group.prometheus_region_0[0].id,
  ]
}

module "monitoring_region_1" {
  count = local.load_tests_enabled

  source = "../../../../modules/ecs/fargate/monitoring"

  providers = {
    aws = aws.accepter
  }

  prefix              = "${local.load_tests_prefix}-r1"
  ecs_cluster_id      = local.infra.ecs_cluster_region_1_id
  vpc_id              = local.infra.vpc_region_1_id
  vpc_private_subnets = local.infra.vpc_region_1_private_subnets
  aws_region          = data.aws_region.region_1.region

  ecs_task_execution_role_arn = local.infra.ecs_task_execution_role_region_1_arn

  prometheus_port = var.load_tests_prometheus_port
  retention_time  = var.load_tests_retention_time

  service_security_group_ids = [
    local.infra.sg_camunda_ports_region_1_id,
    local.infra.sg_package_80_443_region_1_id,
    aws_security_group.prometheus_region_1[0].id,
  ]
}

module "load_generator" {
  count = local.load_tests_enabled

  source = "../../../../modules/ecs/fargate/load-generator"

  prefix              = local.load_tests_prefix
  ecs_cluster_id      = local.infra.ecs_cluster_region_0_id
  vpc_private_subnets = local.infra.vpc_region_0_private_subnets
  aws_region          = data.aws_region.region_0.region

  ecs_task_execution_role_arn = local.infra.ecs_task_execution_role_region_0_arn

  camunda_host = module.orchestration_cluster_region_0.dns_a_record

  # The region-0 execution role already reads this secret for the brokers'
  # own task definition, so no extra IAM is needed here.
  auth_method              = "basic"
  auth_username            = "admin"
  auth_password_secret_arn = local.infra.admin_user_password_secret_region_0_arn

  start_rate = var.load_tests_start_rate

  service_security_group_ids = [
    local.infra.sg_camunda_ports_region_0_id,
    local.infra.sg_package_80_443_region_0_id,
  ]
}
