terraform {
  # >= 1.11: ephemeral input variables and write-only attributes (sensitive_body).
  # Validation may also reference another variable (aks_cluster_id
  # is required exactly when apply_via = run-command).
  required_version = ">= 1.11"
  required_providers {
    helm = {
      # >= 3.1 is REQUIRED: `take_ownership` (adopting objects that were applied
      # by hand before Helm managed them) arrived in 3.1.
      source  = "hashicorp/helm"
      version = ">= 3.1"
    }
    azapi = {
      source  = "Azure/azapi"
      # >= 2.11: azapi_resource_action sensitive_body (write-only), first in 2.11.0.
      version = ">= 2.11"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}
