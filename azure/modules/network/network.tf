resource "azurerm_virtual_network" "aks_vnet" {
  name                = "${var.resource_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "${var.resource_prefix}-aks-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = var.aks_subnet_address_prefix

  service_endpoints = ["Microsoft.KeyVault"]
}

resource "azurerm_subnet" "db_subnet" {
  name                 = "${var.resource_prefix}-db-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = var.db_subnet_address_prefix

  delegation {
    name = "db-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Dedicated subnet for AKS API-server VNet integration
resource "azurerm_subnet" "aks_apiserver_subnet" {
  name                 = "${var.resource_prefix}-aks-apiserver-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = var.apiserver_subnet_address_prefix

  delegation {
    name = "apiserver-delegation"
    service_delegation {
      name = "Microsoft.ContainerService/managedClusters"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action"
      ]
    }
  }
}

# This subnet is used for the private endpoint, as the db_subnet is delegated to the PostgreSQL Flexible Server and cannot be used for the private endpoint
resource "azurerm_subnet" "pe_subnet" {
  name                 = "${var.resource_prefix}-pe-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = var.pe_subnet_address_prefix
}
