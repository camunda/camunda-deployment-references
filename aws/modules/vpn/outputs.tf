# rationale about sensitive: if we make a mistake assignment (private instead of public key), we will not leak
output "vpn_ca_key" {
  description = "Private key of the CA Root used for x509 auth"
  value       = tls_private_key.ca_private_key.private_key_pem
  sensitive   = true
}
output "vpn_ca_cert" {
  description = "Public key of the CA Root used for x509 auth"
  value       = tls_self_signed_cert.ca_public_key.cert_pem
  sensitive   = true
}
output "vpn_server_cert" {
  description = "Public key of the server cert used for x509 auth"
  value       = tls_locally_signed_cert.server_public_key.cert_pem
  sensitive   = true
}

output "vpn_server_key" {
  description = "Private key of the server cert"
  value       = tls_private_key.server_private_key.private_key_pem
  sensitive   = true
}

output "vpn_clients_keys" {
  description = "Map of the clients public and private keys"
  value = {
    for name in var.client_key_names : name => {
      private_key = tls_private_key.client_private_key[name].private_key_pem
      public_key  = tls_locally_signed_cert.client_public_key[name].cert_pem
    }
  }
  sensitive = true
}

output "vpn_endpoint" {
  description = "Endpoint of the VPN"
  value       = replace(aws_ec2_client_vpn_endpoint.vpn.dns_name, "*.", "")
}
