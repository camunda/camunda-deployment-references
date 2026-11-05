output "peering_connection_id" {
  value       = aws_vpc_peering_connection.this.id
  description = "ID of the VPC peering connection"
}

output "additional_cidr_blocks_a" {
  value       = [var.vpc_cidr_b]
  description = "CIDR to pass as additional_cidr_blocks to the compute and storage layers of region_a, so that the other region reaches them"
}

output "additional_cidr_blocks_b" {
  value       = [var.vpc_cidr_a]
  description = "CIDR to pass as additional_cidr_blocks to the compute layer of region_b"
}
