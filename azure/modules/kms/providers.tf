terraform {
  required_version = ">= 1.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.40"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 2.0"
    }
  }
}
