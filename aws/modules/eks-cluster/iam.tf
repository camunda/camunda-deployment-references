
################################################################################
# IRSA
################################################################################

module "ebs_cs_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.54.0"

  role_name = "${var.name}-ebs-cs-role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  role_policy_arns = {
    policy   = aws_iam_policy.ebs_sc_access.arn
    policy_2 = aws_iam_policy.ebs_sc_access_2.arn
  }
}

# Following role allows cert-manager to do the DNS01 challenge
module "cert_manager_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.54.0"

  role_name = "${var.name}-cert-manager-role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["cert-manager:cert-manager"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.cert_manager_policy.arn
  }
}

# Following role allows external-dns to adjust values in hosted zones
module "external_dns_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.54.0"

  role_name = "${var.name}-external-dns-role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.external_dns_policy.arn
  }
}
