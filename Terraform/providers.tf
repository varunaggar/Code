terraform {
  required_providers {
    azurerm = {
      version = "3.0.1"
      source  = "hashicorp/azurerm"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.7.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  alias           = "Main"
  client_id       = "754f06fd-6161-42ed-858a-d189e0dc9e1a"
  client_secret   = "LB98Q~Er2eJQJoSlFds8FzTN-sehKrritR~2HaFu"
  tenant_id       = "c2efc329-9485-4475-bdc6-267f4b9954ef"
  subscription_id = "4eba850c-01a8-4df2-ab0e-99abc5db481c"

}

provider "azuread" {}


provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  alias           = "FreeTrial"
  client_id       = var.FreeTrialSubscription.client_id
  client_secret   = var.FreeTrialSubscription.client_secret
  tenant_id       = var.FreeTrialSubscription.tenant_id
  subscription_id = var.FreeTrialSubscription.subscription_id

}