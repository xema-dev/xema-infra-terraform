terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = ">= 1.24" # modules/postgres-tenancy/versions.tf says why
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 5.0"
    }
  }
}
