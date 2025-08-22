# Encryption Key for Kubernetes secrets
resource "aws_kms_key" "eks" {
  description             = "${var.name} -  EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.kms_key_tags
}

# E.g. used for Prometheus external scraping to allow the cluster API access to node ports
# The security group is automatically created by AWS and not managed by the EKS module
resource "aws_security_group_rule" "cluster_api_to_nodes" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = module.eks.cluster_security_group_id
  description              = "Cluster API to node access for Prometheus"
}

resource "aws_security_group_rule" "allow_api_access_from_vpc" {
  count = var.private_vpc ? 1 : 0

  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = module.eks.cluster_security_group_id
  cidr_blocks       = module.vpc.private_subnets_cidr_blocks
  description       = "Allow API access from VPC Private subnets IP CIDR"
}
