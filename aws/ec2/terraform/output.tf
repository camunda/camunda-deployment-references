output "bastion_ip" {
  value = aws_instance.bastion.public_ip
}

output "camunda_ips" {
  value = [for instance in aws_instance.camunda : instance.private_ip]
}

output "aws_opensearch_domain" {
  value = "https://${aws_opensearch_domain.opensearch_cluster.endpoint}"
}

output "alb_endpoint" {
  value = aws_lb.main.dns_name
}
