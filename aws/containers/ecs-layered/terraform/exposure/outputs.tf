# Exposure contract: the Camunda layer attaches its rules to these listeners.

output "alb_listener_http_webapp_arn" {
  value       = local.webapp_listener_arn
  description = "Listener for the web apps and OIDC callbacks: HTTPS 443 when a certificate is set, HTTP 80 otherwise"
}

output "alb_listener_http_management_arn" {
  value       = aws_lb_listener.http_management.arn
  description = "Listener on 9600 for the management endpoints. The Camunda layer leaves its rule off by default: the endpoint is unauthenticated."
}

output "nlb_grpc_arn" {
  value       = aws_lb.grpc.arn
  description = "ARN of the network load balancer for gRPC (26500)"
}

output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "DNS name of the ALB. Point your public hostname at it."
}

output "nlb_grpc_dns_name" {
  value       = aws_lb.grpc.dns_name
  description = "DNS name of the gRPC network load balancer"
}

output "public_base_url" {
  value       = local.public_base_url
  description = "Browser-facing base URL (scheme and host). OIDC redirect URIs and issuers are built from it."
}
