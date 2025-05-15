locals {
  resource_prefix     = var.resource_prefix_placeholder # Change this to a name of your choice
  resource_group_name = ""                              # Change this to a name of your choice, if not provided, it will be set to resource_prefix-rg, if provided, it will be used as the resource group name
  location            = "swedencentral"                 # Change this to your desired Azure region
  # renovate: datasource=endoflife-date depName=azure-kubernetes-service versioning=loose
  kubernetes_version = "1.31" # Change this to your desired Kubernetes version (aks - major.minor)
}
