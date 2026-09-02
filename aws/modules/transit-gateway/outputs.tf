output "owner_transit_gateway_id" {
  description = "ID of the Transit Gateway in the owner region"
  value       = aws_ec2_transit_gateway.owner.id
}

output "accepter_transit_gateway_id" {
  description = "ID of the Transit Gateway in the accepter region"
  value       = aws_ec2_transit_gateway.accepter.id
}

output "owner_default_route_table_id" {
  description = "Default route table ID of the owner Transit Gateway"
  value       = aws_ec2_transit_gateway.owner.association_default_route_table_id
}

output "accepter_default_route_table_id" {
  description = "Default route table ID of the accepter Transit Gateway"
  value       = aws_ec2_transit_gateway.accepter.association_default_route_table_id
}

output "peering_attachment_id" {
  description = "ID of the TGW peering attachment (owner side)"
  value       = aws_ec2_transit_gateway_peering_attachment.owner_to_accepter.id
}

output "peering_accepter_attachment_id" {
  description = "ID of the accepted TGW peering attachment (accepter side)"
  value       = aws_ec2_transit_gateway_peering_attachment_accepter.accepter.id
}
