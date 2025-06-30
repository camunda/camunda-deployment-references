locals {
  opensearch_base_domain   = "os.camunda.ie"
  opensearch_custom_domain = "${var.domain_name}.${local.opensearch_base_domain}"
  opensearch_zone_id       = "Z0320975U3XESO24VAVA"
  key_algorithm            = "RSA_2048"
}

resource "aws_route53_record" "opensearch" {
  zone_id = local.opensearch_zone_id
  name    = local.opensearch_custom_domain
  type    = "CNAME"
  ttl     = "300"
  records = [aws_opensearch_domain.opensearch_cluster.endpoint]
}

resource "aws_acm_certificate" "custom_endpoint_cert" {
  domain_name       = local.opensearch_custom_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.custom_endpoint_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.opensearch_zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.custom_endpoint_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_route53_record" "opensearch_custom_endpoint" {
  zone_id = local.opensearch_zone_id
  name    = local.opensearch_custom_domain
  type    = "CNAME"
  ttl     = "300"
  records = [aws_opensearch_domain.opensearch_cluster.domain_endpoint_options[0].custom_endpoint]
}

resource "aws_acmpca_certificate_authority" "private_ca_authority" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = local.key_algorithm
    signing_algorithm = "SHA256WITHRSA"

    subject {
      common_name  = local.opensearch_base_domain
      organization = "Your Organization"
    }
  }
}

resource "aws_acmpca_permission" "private_ca_permission" {
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca_authority.arn
  actions                   = ["IssueCertificate", "GetCertificate", "ListPermissions"]
  principal                 = "acm.amazonaws.com"
}

resource "aws_acm_certificate" "request_cert" {
  domain_name               = local.opensearch_custom_domain
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca_authority.arn
  key_algorithm             = local.key_algorithm

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [time_sleep.wait_30_seconds]
}

resource "time_sleep" "wait_30_seconds" {
  create_duration = "30s"
  depends_on      = [aws_acmpca_certificate_authority.private_ca_authority]
}
