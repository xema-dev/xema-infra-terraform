# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# manage_role_assignments = false is the externally managed RBAC mode: no role assignment is
# planned, and required_role_assignments still lists one grant per (boundary, namespace).

mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id"
      principal_id = "00000000-0000-0000-0000-000000000002"
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

run "managed_plans_the_assignments" {
  command = plan
  plan_options {
    target = [azurerm_role_assignment.store]
  }

  assert {
    condition     = length(azurerm_role_assignment.store) == 2 && length(output.required_role_assignments) == 2
    error_message = "one role assignment and one required grant per (boundary, namespace)."
  }
}

run "external_plans_none_and_still_lists_them" {
  command = plan
  plan_options {
    target = [azurerm_role_assignment.store]
  }

  variables {
    manage_role_assignments = false
  }

  assert {
    condition     = length(azurerm_role_assignment.store) == 0
    error_message = "no role assignment is planned in externally managed RBAC mode."
  }
  assert {
    condition = [for r in output.required_role_assignments : r.role_definition_name] == ["Key Vault Secrets User", "Key Vault Secrets User"] && alltrue([
      for r in output.required_role_assignments : r.scope == var.secret_stores["app"].key_vault_id && r.principal_type == "ServicePrincipal" && r.principal_id == "00000000-0000-0000-0000-000000000002"
    ])
    error_message = "the required grants are the same tuples as when the module manages them."
  }
}
