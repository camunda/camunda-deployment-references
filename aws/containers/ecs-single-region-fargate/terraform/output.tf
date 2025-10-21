# converting array to string since opensearch is always a single instance
output "aws_opensearch_domain" {
  value       = "https://${join("", module.opensearch_domain[*].opensearch_domain_endpoint)}"
  description = "(Optional) The endpoint of the OpenSearch domain."
}

# converting array to string since ALB is always a single instance
output "alb_endpoint" {
  value       = join("", aws_lb.main[*].dns_name)
  description = "(Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp."
}

output "nlb_endpoint" {
  value       = join("", aws_lb.grpc[*].dns_name)
  description = "(Optional) The DNS name of the Network Load Balancer (NLB) to access the Camunda Core."
}


output "grafana_endpoint" {
  value       = var.enable_alb ? "http://${aws_lb.main[0].dns_name}:3000" : null
  description = "Grafana endpoint if ALB enabled"
}
