terraform {
  # >= 1.9: variable validation may reference another variable (aks_cluster_id
  # is required exactly when apply_via = run-command).
  required_version = ">= 1.9"
  required_providers {
    helm = {
      # >= 3.1 is REQUIRED: `take_ownership` (adopting objects that were applied
      # by hand before Helm managed them) arrived in 3.1.
      source  = "hashicorp/helm"
      version = ">= 3.1"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}
