mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/i" }
  }
  mock_data "azurerm_kubernetes_service_versions" {
    defaults = { latest_version = "1.31.1" }
  }
}

override_resource {
  target = azurerm_kubernetes_cluster.this
  values = {
    kube_config = [{ host = "h", client_certificate = "a", client_key = "b", cluster_ca_certificate = "c", username = "u", password = "p" }]
  }
}

variables {
  name               = "t-aks"
  region             = "westeurope"
  kubernetes_version = "1.31"
  default_pool_id    = "generic"
  vnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/v"
  node_subnet_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/v/subnets/s"
  node_pools         = { generic = { size = "Standard_D4s_v5", node_count = 1 } }
}

run "default_plan_sets_cilium_engine" {
  command = plan
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "cilium" && azurerm_kubernetes_cluster.this.network_profile[0].network_data_plane == "cilium"
    error_message = "the default plan must enable the Cilium dataplane and policy engine."
  }
}

run "calico_keeps_azure_dataplane" {
  command = plan
  variables {
    network_policy_engine = "calico"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "calico" && azurerm_kubernetes_cluster.this.network_profile[0].network_data_plane == "azure"
    error_message = "calico runs on the Azure dataplane."
  }
}

run "no_engine_is_refused" {
  command = plan
  variables {
    network_policy_engine = "none"
  }
  expect_failures = [var.network_policy_engine]
}
