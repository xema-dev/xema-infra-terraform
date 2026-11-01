# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# manage_role_assignments = false is the externally managed RBAC mode: no role assignment is
# planned, and required_role_assignments still lists every grant the module would make. Only the
# grants (and the identity they use) are targeted: the cluster itself is not under test.

mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id"
      principal_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}

variables {
  node_pools = {
    system = { size = "Standard_D4s_v5", node_count = 1 }
  }
  default_pool_id    = "system"
  name               = "k-test"
  region             = "westeurope"
  kubernetes_version = "1.34"
  vnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net/providers/Microsoft.Network/virtualNetworks/vnet"
  node_subnet_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks"
  route_table_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net/providers/Microsoft.Network/routeTables/rt"
}

run "managed_plans_the_assignments" {
  command = plan
  plan_options {
    target = [azurerm_role_assignment.cluster_network, azurerm_role_assignment.cluster_route_table]
  }

  assert {
    condition     = length(azurerm_role_assignment.cluster_network) == 1 && length(azurerm_role_assignment.cluster_route_table) == 1
    error_message = "by default both Network Contributor grants are planned."
  }
  assert {
    condition     = length(output.required_role_assignments) == 2
    error_message = "required_role_assignments lists the VNet and the route table grants."
  }
}

run "external_plans_none_and_still_lists_them" {
  command = plan
  plan_options {
    target = [azurerm_role_assignment.cluster_network, azurerm_role_assignment.cluster_route_table]
  }

  variables {
    manage_role_assignments = false
  }

  assert {
    condition     = length(azurerm_role_assignment.cluster_network) == 0 && length(azurerm_role_assignment.cluster_route_table) == 0
    error_message = "no role assignment is planned in externally managed RBAC mode."
  }
  assert {
    condition = output.required_role_assignments == [
      { scope = var.vnet_id, role_definition_name = "Network Contributor", principal_id = "00000000-0000-0000-0000-000000000002", principal_type = "ServicePrincipal" },
      { scope = var.route_table_id, role_definition_name = "Network Contributor", principal_id = "00000000-0000-0000-0000-000000000002", principal_type = "ServicePrincipal" },
    ]
    error_message = "the required grants are the same tuples as when the module manages them."
  }
}
