terraform {
  required_version = ">= 1.6"
  required_providers {
    helm = {
      # >= 3.0 is REQUIRED, not conservative: the list-shaped `set = [...]`
      # and the `kubernetes = {}` provider attribute are the v3 schema.
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
  }
}
