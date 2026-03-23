# Azure Provider Configuration for OceanBase Deployment
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
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
  # Use the control-node VM's SystemAssigned managed identity.
  # No az login required - the VM's managed identity has Contributor on the subscription.
  use_msi = true
}

provider "azapi" {
  use_msi = true
}
