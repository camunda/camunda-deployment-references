locals {
  # TODO: harcoded on purpose
  deployment_root_domain = "picsou86.camunda.ie"
  opensearch_zone_id     = "Z0320975U3XESO24VAVA"
  key_algorithm          = "RSA_2048"
}

locals {
  camunda_custom_domain = "camunda.${local.deployment_root_domain}"
}

## ROOT CA

resource "tls_private_key" "root_ca_key" {
  algorithm = lower(local.key_algorithm) == "rsa_2048" ? "RSA" : "ECDSA"
}

resource "tls_self_signed_cert" "root_ca_cert" {
  private_key_pem = tls_private_key.root_ca_key.private_key_pem

  subject {
    common_name  = "My ROOT CA"
    organization = "Your Organization"
  }

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment",
    "digital_signature"
  ]
}

resource "aws_secretsmanager_secret" "root_ca_private_key" {
  name        = "certs/${local.deployment_root_domain}-rootca/private-key"
  description = "Private key for Root CA ${local.deployment_root_domain}"
}

resource "aws_secretsmanager_secret_version" "root_ca_private_key_version" {
  secret_id     = aws_secretsmanager_secret.root_ca_private_key.id
  secret_string = tls_private_key.root_ca_key.private_key_pem
}

resource "aws_secretsmanager_secret" "root_ca_certificate" {
  name        = "certs/${local.deployment_root_domain}-rootca/certificate"
  description = "Self-signed root certificate for ${local.deployment_root_domain}"
}

resource "aws_secretsmanager_secret_version" "root_ca_certificate_version" {
  secret_id     = aws_secretsmanager_secret.root_ca_certificate.id
  secret_string = tls_self_signed_cert.root_ca_cert.cert_pem
}

## SUB Root CA

resource "aws_acmpca_certificate_authority" "sub_ca" {
  type = "SUBORDINATE"
  certificate_authority_configuration {
    key_algorithm     = local.key_algorithm
    signing_algorithm = "SHA256WITHRSA"
    subject {
      common_name  = "Subordinate Root CA"
      organization = "Your Organization"
    }
  }

  revocation_configuration {
    crl_configuration {
      enabled            = false
      expiration_in_days = 1095
    }
  }

  permanent_deletion_time_in_days = 7
}

resource "tls_locally_signed_cert" "sub_ca_cert_signed" {
  cert_request_pem   = aws_acmpca_certificate_authority.sub_ca.certificate_signing_request
  ca_private_key_pem = tls_private_key.root_ca_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.root_ca_cert.cert_pem

  validity_period_hours = 43800

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment",
    "digital_signature"
  ]

  is_ca_certificate = true
}

# Final step to activate the CA using the self-signed certificate
resource "aws_acmpca_certificate_authority_certificate" "sub_ca_cert_import" {
  certificate_authority_arn = aws_acmpca_certificate_authority.sub_ca.arn
  certificate               = tls_locally_signed_cert.sub_ca_cert_signed.cert_pem
  certificate_chain         = tls_self_signed_cert.root_ca_cert.cert_pem
}

resource "aws_acmpca_permission" "private_ca_permission" {
  certificate_authority_arn = aws_acmpca_certificate_authority.sub_ca.arn
  actions                   = ["IssueCertificate", "GetCertificate", "ListPermissions"]
  principal                 = "acm.amazonaws.com"
}

resource "time_sleep" "wait_30_seconds" {
  create_duration = "30s"
  depends_on      = [aws_acmpca_certificate_authority.sub_ca]
}
resource "aws_secretsmanager_secret" "sub_root_ca_certificate" {
  name        = "certs/${local.deployment_root_domain}-subroot-ca/certificate"
  description = "Self-signed sub root certificate for ${local.deployment_root_domain}"
}

resource "aws_secretsmanager_secret_version" "sub_root_ca_certificate_version" {
  secret_id     = aws_secretsmanager_secret.sub_root_ca_certificate.id
  secret_string = tls_locally_signed_cert.sub_ca_cert_signed.cert_pem
}

output "private_ca_authority_arn" {
  value = aws_acmpca_certificate_authority.sub_ca.arn
}

### Camunda certs

resource "tls_private_key" "camunda_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_secretsmanager_secret" "camunda_key_secret" {
  name        = "certs/${local.camunda_custom_domain}/private-key"
  description = "Private key for Camunda ${local.camunda_custom_domain}"
}

resource "aws_secretsmanager_secret_version" "camunda_key_secret_version" {
  secret_id     = aws_secretsmanager_secret.camunda_key_secret.id
  secret_string = tls_private_key.camunda_key.private_key_pem
}

resource "aws_secretsmanager_secret" "camunda_cert_secret" {
  name        = "certs/${local.camunda_custom_domain}/certificate"
  description = "Signed certificate for Camunda ${local.camunda_custom_domain}"
}

resource "aws_secretsmanager_secret_version" "camunda_cert_secret_version" {
  secret_id     = aws_secretsmanager_secret.camunda_cert_secret.id
  secret_string = aws_acmpca_certificate.camunda_signed_cert.certificate
}
resource "tls_cert_request" "camunda_csr" {
  private_key_pem = tls_private_key.camunda_key.private_key_pem

  subject {
    common_name  = local.camunda_custom_domain
    organization = "Your Organization"
  }
}

resource "aws_acmpca_certificate" "camunda_signed_cert" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.sub_ca.arn
  certificate_signing_request = tls_cert_request.camunda_csr.cert_request_pem
  signing_algorithm           = "SHA256WITHRSA"

  validity {
    type  = "DAYS"
    value = 180
  }

  template_arn = "arn:aws:acm-pca:::template/EndEntityCertificate/V1"
}
