terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.34.0"
    }
    random = {
      source  = "registry.terraform.io/hashicorp/random"
      version = "~> 3.7.2"
    }

  }
  backend "azurerm" {
    resource_group_name  = "tfstate"
    storage_account_name = "tfstate1387130601"
    container_name       = "tfstate"
    key                  = "vmname.azure.tfstate"
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = "1b1e1f87-7409-40cb-a45f-112230493f52"
}

resource "random_id" "random" {
  byte_length = 1
}