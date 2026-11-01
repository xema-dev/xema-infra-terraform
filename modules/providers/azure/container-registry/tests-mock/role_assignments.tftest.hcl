# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# manage_role_assignments = false is the externally managed RBAC mode: no role assignment is
# planned, and required_role_assignments still lists every grant the module would make.

mock_provider "azurerm" {
  mock_resource "azurerm_container_registry" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ContainerRegistry/registries/acr"
    }
  }
}

variables {
  name                = "acrtest"
  region              = "westeurope"
  resource_group_name = "rg"
  pull_principal_ids  = { kubelet = "00000000-0000-0000-0000-000000000002" }
}

run "managed_plans_the_assignment" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.pull) == 1 && length(output.required_role_assignments) == 1
    error_message = "by default the AcrPull grant is planned and listed."
  }
}

run "external_plans_none_and_still_lists_it" {
  command = plan

  variables {
    manage_role_assignments = false
  }

  assert {
    condition     = length(azurerm_role_assignment.pull) == 0
    error_message = "no role assignment is planned in externally managed RBAC mode."
  }
  assert {
    condition = output.required_role_assignments == [
      { scope = azurerm_container_registry.this.id, role_definition_name = "AcrPull", principal_id = "00000000-0000-0000-0000-000000000002", principal_type = null },
    ]
    error_message = "the required grant is the same tuple as when the module manages it."
  }
}
