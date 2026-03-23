terraform {
  required_providers {
    azurerm = "~> 4.5"
    azapi   = {
      source  = "Azure/azapi"
      version = ">= 2.8"
    }
  }
}

provider "azapi" {
  use_msi = true
  subscription_id = var.ARM_SUBSCRIPTION_ID
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
  use_msi = true
  subscription_id = var.ARM_SUBSCRIPTION_ID
  resource_provider_registrations = "none"
}