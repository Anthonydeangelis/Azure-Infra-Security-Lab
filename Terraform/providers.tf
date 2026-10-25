terraform {
  required_version = "=1.16.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
  storage_use_azuread = true

  subscription_id = var.subscription_id
}
