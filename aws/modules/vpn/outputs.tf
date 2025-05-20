output "vpn_ca_keys_s3_urls" {
  description = "Map of S3 URLs for client private and public keys"
  value = {
    private_key_s3_url = "s3://${var.s3_bucket_name}/${local.ca_private_key_object_key}"
    public_key_s3_url  = "s3://${var.s3_bucket_name}/${local.ca_public_key_object_key}"
  }
}

output "vpn_server_keys_s3_urls" {
  description = "Map of S3 URLs for client private and public keys"
  value = {
    private_key_s3_url = "s3://${var.s3_bucket_name}/${local.server_private_key_object_key}"
    public_key_s3_url  = "s3://${var.s3_bucket_name}/${local.server_public_key_object_key}"
  }
}

output "vpn_client_keys_s3_urls" {
  description = "Map of S3 URLs for client private and public keys"
  value = {
    for name in var.client_key_names : name => {
      private_key_s3_url = "s3://${var.s3_bucket_name}/${local.client_keys[name].private_key_object_key}"
      public_key_s3_url  = "s3://${var.s3_bucket_name}/${local.client_keys[name].public_key_object_key}"
    }
  }
}

output "vpn_client_configs" {
  description = "Map of OpenVPN configs of each client"
  value = {
    for name in var.client_key_names :
    name => "s3://${var.s3_bucket_name}/${var.s3_ca_directory}/client-configs/${name}.ovpn"
  }
}

output "vpn_endpoint" {
  description = "Endpoint of the VPN"
  value       = replace(aws_ec2_client_vpn_endpoint.vpn.dns_name, "^\\*\\.", "")
}
