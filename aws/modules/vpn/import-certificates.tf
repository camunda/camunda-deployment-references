resource "aws_acm_certificate" "vpn_cert" {
  private_key       = tls_private_key.server_private_key.private_key_pem
  certificate_body  = tls_locally_signed_cert.server_public_key.cert_pem
  certificate_chain = tls_self_signed_cert.ca_public_key.cert_pem
}

resource "aws_acm_certificate" "ca_cert" {
  private_key      = tls_private_key.ca_private_key.private_key_pem
  certificate_body = tls_self_signed_cert.ca_public_key.cert_pem
}
