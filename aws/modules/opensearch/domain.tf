locals {
  # TODO: harcoded on purpose
  deployment_root_domain = "picsou2.camunda.ie"
  opensearch_zone_id     = "Z0320975U3XESO24VAVA"
  key_algorithm          = "RSA_2048"
}

locals {
  opensearch_custom_domain = "os.${local.deployment_root_domain}"
}

data "aws_acmpca_certificate_authority" "private_ca_authority" {
  arn = var.custom_root_ca_arn
}

## CERT FOR OS
resource "aws_acm_certificate" "opensearch_cert" {
  domain_name               = local.opensearch_custom_domain
  certificate_authority_arn = data.aws_acmpca_certificate_authority.private_ca_authority.arn
  validation_method         = "DNS"

  tags = {
    Name = "OS ACM cert for ${local.opensearch_custom_domain}"
  }
}
resource "aws_route53_record" "opensearch_cert_validation" {
  name    = tolist(aws_acm_certificate.opensearch_cert.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.opensearch_cert.domain_validation_options)[0].resource_record_type
  zone_id = local.opensearch_zone_id
  records = [tolist(aws_acm_certificate.opensearch_cert.domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "opensearch_cert_validation" {
  certificate_arn         = aws_acm_certificate.opensearch_cert.arn
  validation_record_fqdns = [aws_route53_record.opensearch_cert_validation.fqdn]
}

resource "aws_route53_record" "opensearch" {
  zone_id = local.opensearch_zone_id
  name    = local.opensearch_custom_domain
  type    = "CNAME"
  ttl     = "300"
  records = [aws_opensearch_domain.opensearch_cluster.endpoint]
}
