locals {
  # TODO: harcoded on purpose
  deployment_root_domain = "picsou.camunda.ie"
  opensearch_zone_id     = "Z0320975U3XESO24VAVA"
  key_algorithm          = "RSA_2048"
}

locals {
  camunda_custom_domain = "camunda.${local.deployment_root_domain}"
}

## ROOT CA
resource "aws_acmpca_certificate_authority" "private_ca_authority" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = local.key_algorithm
    signing_algorithm = "SHA256WITHRSA"

    subject {
      common_name  = local.deployment_root_domain
      organization = "Your Organization"
    }
  }
}

resource "tls_private_key" "root_ca_key" {
  algorithm = lower(local.key_algorithm) == "rsa_2048" ? "RSA" : "ECDSA"
}

# Self-signed certificate to activate the Root CA
resource "tls_self_signed_cert" "root_ca_cert" {
  private_key_pem = tls_private_key.root_ca_key.private_key_pem

  subject {
    common_name  = local.deployment_root_domain
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

resource "null_resource" "save_csr" {
  provisioner "local-exec" {
    command = <<EOT
      echo '${aws_acmpca_certificate_authority.private_ca_authority.certificate_signing_request}' | base64 --decode > ./ca.csr
    EOT
  }
  depends_on = [aws_acmpca_certificate_authority.private_ca_authority]
}

resource "null_resource" "sign_csr" {
  provisioner "local-exec" {
    command = <<EOT
      openssl x509 -req -in ./ca.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out ./ca_cert.pem -days 3650 -sha256
    EOT
  }
  depends_on = [null_resource.save_csr]
}

data "local_file" "signed_cert" {
  filename   = "${path.module}/ca_cert.pem"
  depends_on = [null_resource.sign_csr]
}


# Final step to activate the CA using the self-signed certificate
resource "aws_acmpca_certificate_authority_certificate" "root_ca_certificate" {
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca_authority.arn

  certificate       = data.local_file.signed_cert.content
  certificate_chain = data.local_file.signed_cert.content
}

resource "aws_acmpca_permission" "private_ca_permission" {
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca_authority.arn
  actions                   = ["IssueCertificate", "GetCertificate", "ListPermissions"]
  principal                 = "acm.amazonaws.com"
}

resource "time_sleep" "wait_30_seconds" {
  create_duration = "30s"
  depends_on      = [aws_acmpca_certificate_authority.private_ca_authority]
}

resource "aws_secretsmanager_secret" "root_ca_private_key" {
  name        = "certs/${local.deployment_root_domain}/private-key"
  description = "Private key for Root CA ${local.deployment_root_domain}"
}

resource "aws_secretsmanager_secret_version" "root_ca_private_key_version" {
  secret_id     = aws_secretsmanager_secret.root_ca_private_key.id
  secret_string = tls_private_key.root_ca_key.private_key_pem
}

resource "aws_secretsmanager_secret" "root_ca_certificate" {
  name        = "certs/${local.deployment_root_domain}/certificate"
  description = "Self-signed root certificate for ${local.deployment_root_domain}"
}

resource "aws_secretsmanager_secret_version" "root_ca_certificate_version" {
  secret_id     = aws_secretsmanager_secret.root_ca_certificate.id
  secret_string = tls_self_signed_cert.root_ca_cert.cert_pem
}

output "private_ca_authority_arn" {
  value = aws_acmpca_certificate_authority.private_ca_authority.arn
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
  certificate_authority_arn   = aws_acmpca_certificate_authority.private_ca_authority.arn
  certificate_signing_request = tls_cert_request.camunda_csr.cert_request_pem
  signing_algorithm           = "SHA256WITHRSA"

  validity {
    type  = "DAYS"
    value = 365
  }

  template_arn = "arn:aws:acm-pca:::template/EndEntityCertificate/V1"
}
