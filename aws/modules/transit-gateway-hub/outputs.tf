output "transit_gateway_id" {
  description = "ID of the regional Transit Gateway"
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_route_table_id" {
  description = "Default association route table ID of the regional Transit Gateway"
  value       = aws_ec2_transit_gateway.this.association_default_route_table_id
}

output "vpc_attachment_id" {
  description = "ID of the VPC attachment of the local cluster VPC"
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}
