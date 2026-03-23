terraform {
  required_providers {
    azurerm = "~> 4.5"
    azapi   = {
      source  = "Azure/azapi"
      version = ">= 2.8"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}

provider "azapi" {}

provider "azurerm" {
  features {}
  subscription_id = var.ARM_SUBSCRIPTION_ID
}
