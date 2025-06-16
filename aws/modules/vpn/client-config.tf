# Generate the VPN configuration content for each client
locals {
  vpn_configs = {
    for name in var.client_key_names : name => templatefile("${path.module}/vpn_config.tmpl", {
      dns_name           = replace(aws_ec2_client_vpn_endpoint.vpn.dns_name, "*.", "")
      server_common_name = var.server_common_name
      ca_cert_pem        = tls_self_signed_cert.ca_public_key.cert_pem
      client_cert_pem    = tls_locally_signed_cert.client_public_key[name].cert_pem
      client_key_pem     = tls_private_key.client_private_key[name].private_key_pem
    })
  }
}

# Output the VPN configuration content for each client
output "vpn_configs" {
  value     = local.vpn_configs
  sensitive = true
}
