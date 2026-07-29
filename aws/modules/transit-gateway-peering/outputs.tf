output "peering_attachment_id" {
  description = "ID of the Transit Gateway peering attachment (owner side)"
  value       = aws_ec2_transit_gateway_peering_attachment.this.id
}

output "peering_accepter_attachment_id" {
  description = "ID of the accepted Transit Gateway peering attachment (accepter side)"
  value       = aws_ec2_transit_gateway_peering_attachment_accepter.this.id
}
