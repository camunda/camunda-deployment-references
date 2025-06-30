locals {
  opensearch_custom_domain = "${var.domain_name}.os.camunda.ie"
  opensearch_zone_id       = "Z0320975U3XESO24VAVA"
}
resource "aws_route53_record" "opensearch" {
  # TODO: temp hard coded
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
