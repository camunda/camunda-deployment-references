resource "aws_route53_record" "opensearch" {
  # TODO: temp hard coded
  zone_id = "Z0320975U3XESO24VAVA"
  name    = "${var.domain_name}.os.camunda.ie"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_opensearch_domain.opensearch_cluster.endpoint]
}
