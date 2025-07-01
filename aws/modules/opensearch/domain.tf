locals {
  deployment_root_domain = "${var.domain_name}.camunda.ie"
  opensearch_zone_id     = "Z0320975U3XESO24VAVA"
  key_algorithm          = "RSA_2048"
}

locals {
  opensearch_custom_domain = "os.${local.deployment_root_domain}"
  camunda_custom_domain    = "camunda.${local.deployment_root_domain}"
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


resource "aws_acmpca_permission" "private_ca_permission" {
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca_authority.arn
  actions                   = ["IssueCertificate", "GetCertificate", "ListPermissions"]
  principal                 = "acm.amazonaws.com"
}


resource "time_sleep" "wait_30_seconds" {
  create_duration = "30s"
  depends_on      = [aws_acmpca_certificate_authority.private_ca_authority]
}

## CERT FOR OS

resource "tls_private_key" "cert_os_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
resource "aws_secretsmanager_secret" "opensearch_key_secret" {
  name        = "certs/${local.opensearch_custom_domain}/private-key"
  description = "Private key for OS ${local.opensearch_custom_domain}"
}

resource "aws_secretsmanager_secret_version" "opensearch_key_secret_version" {
  secret_id     = aws_secretsmanager_secret.opensearch_key_secret.id
  secret_string = tls_private_key.cert_os_key.private_key_pem
}

resource "tls_cert_request" "opensearch_csr" {
  private_key_pem = tls_private_key.cert_os_key.private_key_pem

  subject {
    common_name  = local.opensearch_custom_domain
    organization = "Your Organization"
  }
}

resource "aws_acmpca_certificate" "signed_cert" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.private_ca_authority.arn
  certificate_signing_request = tls_cert_request.opensearch_csr.cert_request_pem
  signing_algorithm           = "SHA256WITHRSA"

  validity {
    type  = "DAYS"
    value = 365
  }

  template_arn = "arn:aws:acm-pca:::template/EndEntityCertificate/V1"
}

resource "aws_route53_record" "opensearch" {
  zone_id = local.opensearch_zone_id
  name    = local.opensearch_custom_domain
  type    = "CNAME"
  ttl     = "300"
  records = [aws_opensearch_domain.opensearch_cluster.endpoint]
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
