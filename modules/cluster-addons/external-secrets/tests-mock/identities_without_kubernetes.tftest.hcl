# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# The Azure identity half (identities, federated credentials, role assignments) is planned on
# its own: only the azurerm resources are targeted, and the helm provider is a mock that is never
# asked for anything. The in-cluster SecretStore releases are the only resources that wait for
# the namespaces (terraform_data.namespaces_ready).

mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id"
    }
  }
}
mock_provider "helm" {}

variables {
  region              = "westeurope"
  resource_group_name = "rg"
  oidc_issuer_url     = "https://oidc.example/issuer/"
  secret_stores = {
    app = {
      namespaces   = ["ns-a", "ns-b"]
      key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv"
      vault_uri    = "https://kv.vault.azure.net/"
    }
  }
}

run "identity_half_plans_without_namespaces" {
  command = plan
  plan_options {
    target = [azurerm_role_assignment.store, azurerm_federated_identity_credential.store]
  }

  assert {
    condition     = length(azurerm_role_assignment.store) == 2 && length(azurerm_federated_identity_credential.store) == 2
    error_message = "one role assignment and one federated credential per (boundary, namespace)."
  }
  assert {
    condition     = azurerm_federated_identity_credential.store["app/ns-a"].subject == "system:serviceaccount:ns-a:secret-store"
    error_message = "the credential federates to the service account of its namespace, which need not exist yet."
  }
  assert {
    condition     = azurerm_role_assignment.store["app/ns-b"].role_definition_name == "Key Vault Secrets User"
    error_message = "only Key Vault Secrets User is granted."
  }
}

run "full_plan_carries_the_namespace_roster_to_the_in_cluster_half" {
  command = plan
  variables {
    namespaces_ready = ["ns-a", "ns-b"]
  }

  assert {
    condition     = length(terraform_data.namespaces_ready.input) == 2 && length(helm_release.secret_store) == 2
    error_message = "the SecretStore releases wait for terraform_data.namespaces_ready."
  }
}
