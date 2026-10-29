# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# HAM-92: the opt-in "service_endpoint" network access for the key vaults and the
# storage account. The default stays private endpoints; service_endpoint mode
# builds no private endpoint for those services and closes them with a network
# ACL that admits only service_endpoint_subnet_ids. Postgres and the cache are
# unaffected. The cluster and in-cluster areas are off: only the cloud half is planned.
# The ACL each module renders is proven in the modules' own tests-mock
# (providers/azure/secrets-backend, providers/azure/object-bucket).

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
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id"
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

run "default_is_private_endpoints" {
  command = plan

  assert {
    condition     = length(module.operator_vault_private_endpoint) == 1 && length(module.boundary_vault_private_endpoint) == 1
    error_message = "by default every key vault gets a private endpoint."
  }
  assert {
    condition     = toset(keys(module.private_endpoint)) == toset(["blob", "redis", "postgres"])
    error_message = "by default storage, cache and postgres get their private endpoints."
  }
  assert {
    condition     = !local.key_vault_service_endpoint && !local.storage_service_endpoint && local.cache_private && local.private_backing_services && !local.key_vault_public_access && !local.storage_public_access && local.service_endpoint_network_rules == null
    error_message = "the default is private for the key vaults, storage and cache: no service-endpoint ACL, public access off."
  }
}

run "service_endpoint_mode_drops_kv_and_storage_endpoints" {
  command = plan

  variables {
    key_vault_network_access        = "service_endpoint"
    backing_services_network_access = "service_endpoint"
    service_endpoint_subnet_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/net-rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/mgmt",
    ]
  }

  assert {
    condition     = length(module.operator_vault_private_endpoint) == 0 && length(module.boundary_vault_private_endpoint) == 0
    error_message = "service_endpoint mode builds no key vault private endpoint."
  }
  assert {
    condition     = toset(keys(module.private_endpoint)) == toset(["redis", "postgres"])
    error_message = "service_endpoint mode drops only the storage endpoint: the cache (no service endpoint) and postgres keep theirs."
  }
  assert {
    condition     = local.key_vault_service_endpoint && local.storage_service_endpoint && local.cache_private && local.key_vault_public_access && local.storage_public_access
    error_message = "service_endpoint mode switches the vaults and storage to service endpoints (public access on, closed by the ACL) and keeps the cache private."
  }
  assert {
    condition     = tolist(local.service_endpoint_network_rules.virtual_network_subnet_ids) == tolist(var.service_endpoint_subnet_ids)
    error_message = "the ACL handed to the vault and storage modules admits exactly service_endpoint_subnet_ids."
  }
}

run "service_endpoint_needs_subnets" {
  command = plan

  variables {
    key_vault_network_access = "service_endpoint"
  }

  expect_failures = [terraform_data.input_guards]
}

run "unknown_mode_is_refused" {
  command = plan

  variables {
    key_vault_network_access = "public"
  }

  expect_failures = [var.key_vault_network_access]
}
