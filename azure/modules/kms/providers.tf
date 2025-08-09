terraform {
  required_version = ">= 1.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.19"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}
