terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2"
    }
    random = {
      source  = "registry.terraform.io/hashicorp/random"
      version = "~> 3.1.0"
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
}

resource "random_id" "random" {
  byte_length = 1
}