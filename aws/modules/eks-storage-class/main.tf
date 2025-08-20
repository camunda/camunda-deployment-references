
variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

# gp3 storage class
resource "kubernetes_storage_class_v1" "ebs_sc" {

  metadata {
    name = "ebs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Retain"
  parameters = {
    type = "gp3" # starting eks 1.30, gp3 is the default
  }
  volume_binding_mode = "WaitForFirstConsumer"

  depends_on = [
    time_sleep.eks_cluster_warmup
  ]
}
