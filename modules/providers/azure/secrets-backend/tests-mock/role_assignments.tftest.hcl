# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# manage_role_assignments = false is the externally managed RBAC mode: no azurerm_role_assignment
# is planned, and required_role_assignments still lists every grant the module would make.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv"
    }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id"
      principal_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}
mock_provider "time" {}

variables {
  name                          = "kv-test"
  region                        = "westeurope"
  resource_group_name           = "rg"
  secret_names                  = ["seed"]
  secret_values                 = { seed = "x" }
  public_network_access_enabled = false
  workload_identity = {
    enabled                   = true
    oidc_issuer_url           = "https://oidc.example/issuer/"
    service_account_namespace = "ns"
    service_account_name      = "sa"
  }
}

run "managed_plans_the_assignments" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.deployer) == 1 && length(azurerm_role_assignment.reader) == 1
    error_message = "by default the deployer and reader role assignments are planned."
  }
  assert {
    condition     = length(output.required_role_assignments) == 2
    error_message = "required_role_assignments lists the deployer and the reader grants."
  }
}

run "external_plans_none_and_still_lists_them" {
  command = plan

  variables {
    manage_role_assignments = false
  }

  assert {
    condition     = length(azurerm_role_assignment.deployer) == 0 && length(azurerm_role_assignment.reader) == 0
    error_message = "no role assignment is planned in externally managed RBAC mode."
  }
  assert {
    condition = output.required_role_assignments == [
      { scope = azurerm_key_vault.this.id, role_definition_name = "Key Vault Secrets Officer", principal_id = "00000000-0000-0000-0000-000000000001" },
      { scope = azurerm_key_vault.this.id, role_definition_name = "Key Vault Secrets User", principal_id = "00000000-0000-0000-0000-000000000002" },
    ]
    error_message = "the required grants are the same tuples as when the module manages them."
  }
}

run "deployer_gate_still_applies" {
  command = plan

  variables {
    grant_deployer_secrets_officer = false
  }

  assert {
    condition     = length(azurerm_role_assignment.deployer) == 0 && length(output.required_role_assignments) == 1
    error_message = "grant_deployer_secrets_officer = false drops the deployer grant from both the resource and the list."
  }
}
