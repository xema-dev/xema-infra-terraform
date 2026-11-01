# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# manage_role_assignments = false is the externally managed RBAC mode: the stack plans no role
# assignment, and its required_role_assignments output still lists the same grants. The resource
# counts are proven in each module's own tests-mock; here the stack threads the input to every
# module and concatenates their lists. The cluster and in-cluster areas are off.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "00000000-0000-0000-0000-000000000001"
    }
  }
  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      oidc_issuer_url = "https://oidc.example/issuer/"
    }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      principal_id = "00000000-0000-0000-0000-000000000002"
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id"
    }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv"
      vault_uri = "https://kv.vault.azure.net/"
    }
  }
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sa"
    }
  }
  mock_resource "azurerm_redis_cache" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Cache/redis/redis"
    }
  }
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/pg"
    }
  }
}
mock_provider "postgresql" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "keycloak" {}

variables {
  deployment_name     = "acme-dev"
  environment         = "dev"
  region              = "westeurope"
  resource_group_name = "rg"
  platform_databases  = []
  workload_namespaces = []

  enable_cluster             = false
  enable_dns                 = false
  enable_rwx_storage         = false
  enable_workload_namespaces = false
  enable_gateway_tls         = false
  enable_identity_realm      = false

  enable_managed_postgres = true
  postgres_network_access = "private_endpoint"
  enable_object_storage   = true
  enable_secrets_backend  = true
  enable_cache            = true
  secret_store_boundaries = {
    app = { namespaces = ["app"], vault_name = "acme-dev-app" }
  }

  network = {
    resource_group_name        = "net-rg"
    vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/virtualNetworks/vnet"
    aks_subnet_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks"
    postgres_subnet_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/pg"
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/pe"
    private_dns_zone_ids = {
      vault    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
      blob     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      redis    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/privateDnsZones/privatelink.redis.cache.windows.net"
      postgres = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"
    }
  }
}


run "managed_lists_the_grants" {
  command = plan

  assert {
    condition     = length(output.required_role_assignments) == 2
    error_message = "the operator vault's deployer grant and the boundary store grant are listed."
  }
}

run "external_lists_the_same_grants" {
  command = plan

  variables {
    manage_role_assignments = false
  }

  assert {
    condition = output.required_role_assignments == [
      { scope = module.secrets_backend[0].key_vault_id, role_definition_name = "Key Vault Secrets Officer", principal_id = "00000000-0000-0000-0000-000000000001" },
      { scope = module.boundary_vault["app"].key_vault_id, role_definition_name = "Key Vault Secrets User", principal_id = "00000000-0000-0000-0000-000000000002" },
    ]
    error_message = "externally managed RBAC lists the same tuples the stack grants by default."
  }
}
