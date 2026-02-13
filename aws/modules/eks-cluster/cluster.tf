# https://github.com/terraform-aws-modules/terraform-aws-eks
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1"

  name                    = var.name
  kubernetes_version      = var.kubernetes_version
  service_ipv4_cidr       = var.cluster_service_ipv4_cidr
  endpoint_private_access = true # private API communication for nodes within the VPC
  endpoint_public_access  = var.private_vpc ? false : true

  cluster_tags = var.cluster_tags

  addons = {
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      resolve_conflicts_on_create = "OVERWRITE"
    }
    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      resolve_conflicts_on_create = "OVERWRITE"
    }
    vpc-cni = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      resolve_conflicts_on_create = "OVERWRITE"

      before_compute = true
    }
    aws-ebs-csi-driver = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      resolve_conflicts_on_create = "OVERWRITE"

      before_compute           = true
      service_account_role_arn = module.ebs_cs_role.arn
    }
  }

  encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true # https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/

  # Extend cluster security group rules
  security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  # EKS Managed Node Group definitions
  eks_managed_node_groups = {
    services = {
      name            = "services"
      use_name_prefix = false
      labels          = var.np_labels

      ami_type       = var.np_ami_type
      disk_size      = var.np_disk_size
      instance_types = var.np_instance_types
      capacity_type  = var.np_capacity_type

      update_config = {
        max_unavailable = 1
      }

      metadata_options = {
        # EKS v21 default is 1 but we keep it explicitly in here
        http_put_response_hop_limit = 1 # related to https://stackoverflow.com/a/73958206, don't allow pods to assume the role of a node
      }

      use_custom_launch_template = false

      min_size     = var.np_min_node_count
      max_size     = var.np_max_node_count
      desired_size = var.np_desired_node_count

    }

  }

  # creates separate IAM role
  create_iam_role          = true
  iam_role_description     = "${var.name} - EKS managed IAM role"
  iam_role_name            = "${var.name}-eks-iam-role"
  iam_role_use_name_prefix = false
  iam_role_additional_policies = {
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }

  node_security_group_name = "${var.name}-eks-node-sg"

  authentication_mode                      = var.authentication_mode
  access_entries                           = var.access_entries
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
}

# propagation of the IAM can take some time on a freshly created cluster
resource "time_sleep" "eks_cluster_warmup" {
  create_duration = "30s"

  triggers = {
    cluster_name = module.eks.cluster_name
  }

  depends_on = [module.eks]
}
