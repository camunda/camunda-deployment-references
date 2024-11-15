locals {
  rosa_cluster_name = "my-rosa" # Change this to a name of your choice

  rosa_cluster_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c", ]

  rosa_rh_token = "REPLACEME" # Change the token with yours

  rosa_admin_username = "kubeadmin"
  rosa_admin_password = "CHANGEME1234r!" # Change the password of your admin password
}

module "rosa_cluster" {
  source = "git::https://github.com/camunda/camunda-tf-rosa//modules/rosa-hcp?ref=feature/official-doc-integ"

  cluster_name = local.rosa_cluster_name

  availability_zones = local.rosa_cluster_zones

  # Set CIDR ranges or use the defaults
  vpc_cidr_block = "10.0.0.0/16"
  machine_cidr   = "10.0.0.0/18"
  service_cidr   = "10.0.128.0/18"
  pod_cidr       = "10.0.64.0/18"

  offline_access_token = local.rosa_rh_token

  # admin access
  htpasswd_username = local.rosa_admin_username
  htpasswd_password = local.rosa_admin_password

  # Default node type for the OpenShift cluster
  compute_node_instance_type = "m6i.xlarge"
  replicas                   = 3
}

# TODO: set outputs
