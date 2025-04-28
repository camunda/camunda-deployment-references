terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.116.0"
    }
  }
}

provider "azurerm" {
  features {}

  # if you lack RP-registration rights, opt out of auto-registration
  skip_provider_registration = true
}

# 1) Ensure the ContainerService RP itself is registered
resource "azurerm_resource_provider_registration" "container_service" {
  name = "Microsoft.ContainerService"
}

# 2) Turn on the APIServer VNet-integration preview feature
resource "azurerm_resource_provider_registration" "enable_apiserver_vnet" {
  # note: same provider namespace as above
  name = "Microsoft.ContainerService"

  feature {
    name       = "EnableAPIServerVnetIntegrationPreview"
    registered = true
  }

  depends_on = [
    azurerm_resource_provider_registration.container_service
  ]
}
