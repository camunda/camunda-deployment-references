locals {
  # TODO: harcoded on purpose
  deployment_root_domain = "picsou86.camunda.ie"
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

  tags = {
    Name = "OS ACM cert for ${local.opensearch_custom_domain}"
  }
}

resource "aws_route53_record" "opensearch" {
  zone_id = local.opensearch_zone_id
  name    = local.opensearch_custom_domain
  type    = "CNAME"
  ttl     = "300"
  records = [aws_opensearch_domain.opensearch_cluster.endpoint]
}
