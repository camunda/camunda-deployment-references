################################################################
#                     Load test overlay                        #
################################################################

# Absorbed from camunda/camunda-load-tests-ecs: a long-lived Prometheus that
# discovers the Orchestration Cluster through Cloud Map, plus a load generator
# that drives a steady rate of process instances at it.
#
# Off by default. A reference architecture is meant to be copied, and most
# copies do not want a benchmark running next to the cluster; turning it on is
# a deliberate act. With the flag off nothing below is planned, so the golden
# plan of this state is unchanged.
#
# Unlike the repository it came from, this does not pull the reliability-testing
# starter/worker images from registry.camunda.cloud. Those are not publicly
# pullable, and anything here has to work for someone outside Camunda, so the
# generator runs the community benchmark instead. Same reasoning as
# aws/kubernetes/eks-multi-region-rdbms/DEVELOPER.md.

locals {
  load_tests_enabled = var.enable_load_tests ? 1 : 0
  load_tests_prefix  = "${var.prefix}-lt"

  # Flow control bounds how fast the engine accepts writes. The absorbed
  # benchmark ran with an explicit limit so a run measures the engine rather
  # than an unbounded intake queue; the reference architecture leaves the
  # engine's own defaults alone unless asked.
  benchmark_cluster_environment = var.enable_benchmark_cluster_profile ? [
    { name = "CAMUNDA_PROCESSING_FLOWCONTROL_WRITE_ENABLED", value = "true" },
    { name = "CAMUNDA_PROCESSING_FLOWCONTROL_WRITE_LIMIT", value = tostring(var.benchmark_cluster_write_limit) },
    { name = "CAMUNDA_PROCESSING_FLOWCONTROL_WRITE_THROTTLE_ENABLED", value = "true" },
  ] : []
}

# Prometheus listens on a port outside var.ports, so that enabling the overlay
# does not widen the security group the cluster itself uses.
resource "aws_security_group" "prometheus" {
  count = local.load_tests_enabled

  name        = "${local.load_tests_prefix}-prometheus"
  description = "Allow access to the Prometheus UI and API from within the VPC"
  vpc_id      = module.vpc.vpc_id

  # The generator speaks basic auth only. Under authentication_mode = "oidc"
  # the cluster rejects it, so the tasks would start, collect 401s and report
  # zero throughput without ever failing. Stop at plan time instead. Attached
  # here because a module block cannot carry a precondition, and this resource
  # is created by exactly the same flag.
  lifecycle {
    precondition {
      condition     = var.authentication_mode == "basic"
      error_message = "enable_load_tests requires authentication_mode = \"basic\": the load generator wires basic auth only and would collect 401s against an OIDC cluster."
    }
  }

  ingress {
    from_port   = var.load_tests_prometheus_port
    to_port     = var.load_tests_prometheus_port
    protocol    = "TCP"
    cidr_blocks = [module.vpc.vpc_cidr_block]
    description = "Prometheus UI and API, reachable inside the VPC only"
  }

  tags = {
    Name = "${local.load_tests_prefix}-prometheus"
  }
}

module "monitoring" {
  count = local.load_tests_enabled

  source = "../../../../modules/ecs/fargate/monitoring"

  prefix              = local.load_tests_prefix
  ecs_cluster_id      = aws_ecs_cluster.ecs.id
  vpc_id              = module.vpc.vpc_id
  vpc_private_subnets = module.vpc.private_subnets
  aws_region          = data.aws_region.current.region

  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn

  prometheus_port = var.load_tests_prometheus_port
  retention_time  = var.load_tests_retention_time

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
    aws_security_group.prometheus[0].id,
  ]
}

module "load_generator" {
  count = local.load_tests_enabled

  source = "../../../../modules/ecs/fargate/load-generator"

  prefix              = local.load_tests_prefix
  ecs_cluster_id      = aws_ecs_cluster.ecs.id
  vpc_id              = module.vpc.vpc_id
  vpc_private_subnets = module.vpc.private_subnets
  aws_region          = data.aws_region.current.region

  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn

  camunda_host = module.orchestration_cluster.dns_a_record

  # The execution role already reads this secret for the cluster's own task
  # definition, so no extra IAM is needed here.
  auth_method              = "basic"
  auth_username            = "admin"
  auth_password_secret_arn = aws_secretsmanager_secret.orchestration_admin_user_password.arn

  start_rate = var.load_tests_start_rate

  service_security_group_ids = [
    aws_security_group.allow_necessary_camunda_ports_within_vpc.id,
    aws_security_group.allow_package_80_443.id,
  ]
}
