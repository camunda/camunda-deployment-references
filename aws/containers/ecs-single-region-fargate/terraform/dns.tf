resource "aws_service_discovery_private_dns_namespace" "namespace" {
  name        = "${var.prefix}.service.local"
  vpc         = module.vpc.vpc_id
  description = "Namespace for ECS services"
}

resource "aws_service_discovery_service" "discovery" {
  count = var.camunda_count

  name = "${var.prefix}-ecs-${count.index}"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.namespace.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
