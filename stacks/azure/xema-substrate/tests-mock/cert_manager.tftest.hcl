# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# XEMA-5449: install_cert_manager installs cert-manager with no gateway TLS issuer behind it (CRDs,
# Gateway API support off, no ClusterIssuer, no Gateway). In every combination there is exactly one
# cert-manager: the stack's standalone module when enable_gateway_tls is off, else the gateway-tls
# module's own (an issuer needs it; the option alone also asks for it). The cluster is read, not
# created; the cloud areas are off so only the in-cluster half is planned.

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

  enable_managed_postgres   = false
  postgres_ownership_marker = "xema-deploy:managed deployment=acme-dev"
  postgres_network_access   = "private_endpoint"
  enable_object_storage     = false
  enable_secrets_backend    = false
  enable_cache              = false

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

run "option_on_installs_one_standalone_cert_manager_with_gateway_api_off" {
  command = plan

  variables {
    install_cert_manager = true
  }

  assert {
    condition     = length(module.cert_manager) == 1 && module.cert_manager[0].gateway_api_enabled == false
    error_message = "the option installs one standalone cert-manager with Gateway API support off."
  }
  assert {
    condition     = length(module.gateway_tls) == 0 && output.cert_manager_installed
    error_message = "no gateway TLS module, and the stack reports cert-manager installed."
  }
}

run "option_off_without_gateway_tls_installs_none" {
  command = plan

  assert {
    condition     = length(module.cert_manager) == 0 && length(module.gateway_tls) == 0 && !output.cert_manager_installed
    error_message = "the default installs no cert-manager."
  }
}

run "gateway_tls_with_issuer_and_option_has_exactly_one_instance" {
  command = plan

  variables {
    install_cert_manager = true
    enable_gateway_tls   = true
    acme_email           = "ops@example.com"
    tls_solver           = "http01"
    workload_namespaces  = ["apps"]
    gateway_listeners = {
      web = { hostname = "app.example.com", certificate_mode = "managed" }
    }
  }

  assert {
    condition     = length(module.cert_manager) == 0 && length(module.gateway_tls) == 1 && module.gateway_tls[0].cert_manager_installed
    error_message = "gateway TLS owns the one cert-manager: no standalone one next to it."
  }
  assert {
    condition     = output.cert_manager_installed
    error_message = "the stack reports cert-manager installed."
  }
}

run "gateway_tls_with_customer_supplied_certs_and_option_installs_one" {
  command = plan

  variables {
    install_cert_manager = true
    enable_gateway_tls   = true
    workload_namespaces  = ["apps"]
    gateway_listeners = {
      web = { hostname = "app.example.com", certificate_mode = "customer_supplied", secret_name = "app-tls" }
    }
  }

  assert {
    condition     = length(module.cert_manager) == 0 && module.gateway_tls[0].cert_manager_installed
    error_message = "customer_supplied certificates with the option: gateway TLS installs the one cert-manager."
  }
}

run "gateway_tls_with_customer_supplied_certs_without_option_installs_none" {
  command = plan

  variables {
    enable_gateway_tls  = true
    workload_namespaces = ["apps"]
    gateway_listeners = {
      web = { hostname = "app.example.com", certificate_mode = "customer_supplied", secret_name = "app-tls" }
    }
  }

  assert {
    condition     = length(module.cert_manager) == 0 && !module.gateway_tls[0].cert_manager_installed && !output.cert_manager_installed
    error_message = "customer_supplied certificates alone install no cert-manager."
  }
}
