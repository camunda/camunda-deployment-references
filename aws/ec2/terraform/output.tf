# converting array to string since bastion is always a single instance
output "bastion_ip" {
  value = join("", aws_instance.bastion[*].public_ip)
}

output "camunda_ips" {
  value = [for instance in aws_instance.camunda : instance.private_ip]
}

# converting array to string since opensearch is always a single instance
output "aws_opensearch_domain" {
  value = "https://${join("", aws_opensearch_domain.opensearch_cluster[*].endpoint)}"
}

# converting array to string since ALB is always a single instance
output "alb_endpoint" {
  value = join("", aws_lb.main[*].dns_name)
}

output "nlb_endpoint" {
  value = join("", aws_lb.grpc[*].dns_name)
}

output "aws_ami" {
  value       = data.aws_ami.debian.id
  description = "The AMI retrieved from AWS for the latest Debian 12 image. Make sure to once pin the aws_ami variable to avoid recreations."
}

output "private_key" {
  value     = join("", tls_private_key.testing[*].private_key_pem)
  sensitive = true
}

output "public_key" {
  value     = join("", tls_private_key.testing[*].public_key_openssh)
  sensitive = true
}
