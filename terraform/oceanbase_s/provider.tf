# Azure Provider Configuration for OceanBase Standalone Deployment
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.ARM_SUBSCRIPTION_ID
  # Authenticates via az login (local) or SystemAssigned managed identity (on Azure VM).
  # Set use_msi = true when running from control-node VM.
  use_msi                         = false
  resource_provider_registrations = "none"
}
