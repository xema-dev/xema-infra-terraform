# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# manage_role_assignments = false is the externally managed RBAC mode: no role assignment is
# planned, and required_role_assignments still lists every grant the module would make.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_resource "azurerm_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/dnszones/example.test"
    }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id"
      principal_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}

variables {
  domain              = "example.test"
  resource_group_name = "rg"
  region              = "westeurope"
  dns01_workload_identity = {
    enabled         = true
    oidc_issuer_url = "https://oidc.example/issuer/"
  }
}

run "managed_plans_the_assignment" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.dns01) == 1 && length(output.required_role_assignments) == 1
    error_message = "by default the DNS Zone Contributor grant is planned and listed."
  }
}

run "external_plans_none_and_still_lists_it" {
  command = plan

  variables {
    manage_role_assignments = false
  }

  assert {
    condition     = length(azurerm_role_assignment.dns01) == 0
    error_message = "no role assignment is planned in externally managed RBAC mode."
  }
  assert {
    condition = output.required_role_assignments == [
      { scope = azurerm_dns_zone.this.id, role_definition_name = "DNS Zone Contributor", principal_id = "00000000-0000-0000-0000-000000000002" },
    ]
    error_message = "the required grant is the same tuple as when the module manages it."
  }
}

run "no_identity_no_grant" {
  command = plan

  variables {
    dns01_workload_identity = { enabled = false, oidc_issuer_url = "" }
  }

  assert {
    condition     = length(output.required_role_assignments) == 0
    error_message = "without the DNS-01 identity there is nothing to grant."
  }
}
