resource "aws_security_group" "this" {
  name        = "${var.domain_name}-allow-all-internal-access"
  description = "Security group managing access to ${var.domain_name}"

  vpc_id = var.vpc_id

  tags = var.tags
}

resource "aws_security_group_rule" "allow_egress" {
  description = "Allow outgoing traffic for the OpenSearch"

  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = var.cidr_blocks

  security_group_id = aws_security_group.this.id
}

resource "aws_security_group_rule" "allow_ingress" {
  description = "Allow incoming traffic for the OpenSearch on port 443"

  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = var.cidr_blocks

  security_group_id = aws_security_group.this.id
}
