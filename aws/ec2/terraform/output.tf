# converting array to string since bastion is always a single instance
output "bastion_ip" {
  value       = join("", aws_instance.bastion[*].public_ip)
  description = "(Optional) The public IP address of the Bastion instance."
}

output "camunda_ips" {
  value       = [for instance in aws_instance.camunda : instance.private_ip]
  description = "The private IP addresses of the Camunda instances."
}

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
  description = "(Optional) The DNS name of the Network Load Balancer (NLB) to access the Camunda REST API."
}

output "aws_ami" {
  value       = data.aws_ami.debian.id
  description = "The AMI retrieved from AWS for the latest Debian 12 image. Make sure to once pin the aws_ami variable to avoid recreations."
}

output "private_key" {
  value       = join("", tls_private_key.testing[*].private_key_openssh)
  sensitive   = true
  description = "(Optional) This private key is meant for testing purposes only and enabled via the variable `generate_ssh_key_pair`."
}

output "public_key" {
  value       = join("", tls_private_key.testing[*].public_key_openssh)
  sensitive   = true
  description = "(Optional) This public key is meant for testing purposes only and enabled via the variable `generate_ssh_key_pair`. Please supply your own public key via the variable `pub_key_path`."
}
