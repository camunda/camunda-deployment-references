terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.116.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_provider_registration" "container_service" {
  provider_namespace = "Microsoft.ContainerService"
}


resource "azurerm_resource_provider_registration" "aks_apiserver_vnet_preview" {
  provider_namespace = "Microsoft.ContainerService"

  feature {
    name       = "EnableAPIServerVnetIntegrationPreview"
    registered = true
  }

  # ensure the provider is registered first
  depends_on = [
    azurerm_resource_provider_registration.container_service
  ]
}
