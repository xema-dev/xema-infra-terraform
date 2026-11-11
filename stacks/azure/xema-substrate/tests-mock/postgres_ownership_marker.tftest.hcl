# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# The stack refuses to plan without the installation's
# ownership marker (`xema installation import` refuses an unmarked role as
# foreign), and with it every role it creates carries the marker as its comment
# — on a created server and on a consumed one alike.

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

  enable_managed_postgres   = true
  postgres_ownership_marker = "xema-deploy:managed deployment=acme-dev"
  postgres_network_access   = "private_endpoint"
  enable_object_storage     = true
  enable_secrets_backend    = true
  enable_cache              = true
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



run "managed_postgres_marks_every_role" {
  command = plan

  assert {
    condition = (
      toset(keys(module.postgres[0].role_ownership_markers)) == toset(["acme_dev", "acme_dev_provisioner"])
      && alltrue([for marker in values(module.postgres[0].role_ownership_markers) : marker == "xema-deploy:managed deployment=acme-dev"])
    )
    error_message = "every role of the created server must carry postgres_ownership_marker, verbatim."
  }
}

run "consumed_postgres_marks_every_role" {
  command = plan

  variables {
    enable_managed_postgres                       = false
    platform_databases                            = ["identity"]
    existing_postgres_host                        = "pg.example"
    existing_postgres_admin_login                 = "pgadmin"
    existing_postgres_admin_password_key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/shared"
  }

  assert {
    condition = (
      toset(keys(module.postgres_tenancy[0].role_ownership_markers)) == toset(["acme_dev", "acme_dev_provisioner"])
      && alltrue([for marker in values(module.postgres_tenancy[0].role_ownership_markers) : marker == "xema-deploy:managed deployment=acme-dev"])
    )
    error_message = "every role ensured on a consumed server must carry postgres_ownership_marker, verbatim."
  }
}

run "a_stack_without_the_marker_is_refused" {
  command = plan

  variables {
    postgres_ownership_marker = null
  }

  expect_failures = [var.postgres_ownership_marker]
}
