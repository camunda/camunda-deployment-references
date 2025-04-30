# converting array to string since opensearch is always a single instance
output "aws_opensearch_domain" {
  value       = "https://${join("", module.opensearch_domain[*].opensearch_domain_endpoint)}"
  description = "(Optional) The endpoint of the OpenSearch domain."
}

output "aws_opensearch_domain_name" {
  value       = var.enable_opensearch ? local.opensearch_domain_name : ""
  description = "The name of the OpenSearch domain."
}

# converting array to string since ALB is always a single instance
output "alb_endpoint" {
  value       = join("", aws_lb.main[*].dns_name)
  description = "(Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp."
}
