resource "aws_service_discovery_private_dns_namespace" "namespace" {
  name        = "${var.prefix}.service.local"
  vpc         = var.vpc_id
  description = "Namespace for ECS services"
}

resource "aws_service_discovery_service" "discovery" {
  name = "orchestration-cluster"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.namespace.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
  }
}

# ECS Service Connect namespace for service-to-service communication
resource "aws_service_discovery_http_namespace" "service_connect" {
  name        = "${var.prefix}-sc"
  description = "Service Connect namespace for ECS services"
}
