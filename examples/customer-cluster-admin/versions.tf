terraform {
  required_version = ">= 1.11"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.11"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }

  # Placeholder: this root has its OWN state and key, never shared with CI's.
  backend "azurerm" {
    resource_group_name  = "REPLACE-tfstate-rg"
    storage_account_name = "REPLACEtfstate"
    container_name       = "tfstate"
    key                  = "cluster-admin/terraform.tfstate"
    use_azuread_auth     = true
  }
}
