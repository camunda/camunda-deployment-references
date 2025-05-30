# CA
resource "tls_private_key" "ca_private_key" {
  algorithm = var.ca_key_algorithm
  rsa_bits  = var.ca_key_bits
}

resource "tls_self_signed_cert" "ca_public_key" {
  private_key_pem = tls_private_key.ca_private_key.private_key_pem

  subject {
    common_name  = var.ca_common_name
    organization = var.ca_organization
  }

  is_ca_certificate     = true
  validity_period_hours = var.ca_validity_period_hours
  early_renewal_hours   = var.ca_early_renewal_hours

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

# Server cert signed by the Root CA
resource "tls_private_key" "server_private_key" {
  algorithm = var.key_algorithm
  rsa_bits  = var.key_bits
}

resource "tls_cert_request" "server_csr" {
  private_key_pem = tls_private_key.server_private_key.private_key_pem

  subject {
    common_name = var.server_common_name
  }
}

resource "tls_locally_signed_cert" "server_public_key" {
  cert_request_pem   = tls_cert_request.server_csr.cert_request_pem
  ca_private_key_pem = tls_private_key.ca_private_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca_public_key.cert_pem

  validity_period_hours = var.server_certificate_validity_period_hours
  set_subject_key_id    = true

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

# Client cert signed by the Root CA
resource "tls_private_key" "client_private_key" {
  for_each  = toset(var.client_key_names)
  algorithm = var.key_algorithm
  rsa_bits  = var.key_bits
}

resource "tls_cert_request" "client_csr" {
  for_each = tls_private_key.client_private_key

  private_key_pem = each.value.private_key_pem

  subject {
    common_name = "${var.ca_common_name}.${each.key}"
  }
}

resource "tls_locally_signed_cert" "client_public_key" {
  for_each           = tls_cert_request.client_csr
  cert_request_pem   = each.value.cert_request_pem
  ca_private_key_pem = tls_private_key.ca_private_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca_public_key.cert_pem

  validity_period_hours = var.client_certificate_validity_period_hours
  set_subject_key_id    = true

  allowed_uses = [
    "client_auth",
    "digital_signature",
  ]
}
