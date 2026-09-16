terraform {
  required_version = ">= 1.6"

  # Remote state in a PRIVATE Azure Storage container. Backend config is partial:
  # the account/container/key live in backend.hcl, NOT here (that file holds
  # deployment-specific values and is git-ignored). Init with:
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example for the shape.
  backend "azurerm" {}
}

module "substrate" {
  source = "../../stacks/azure/xema-substrate"

  # --- identity: everything else is derived from these ---
  deployment_name = var.deployment_name
  environment     = var.environment
  region          = var.region
  apex_domain     = var.apex_domain
  tags            = var.tags

  # --- overrides for the four GLOBALLY-unique derived names (empty = derive) ---
  key_vault_name       = var.key_vault_name
  storage_account_name = var.storage_account_name
  postgres_server_name = var.postgres_server_name
  redis_cache_name     = var.redis_cache_name

  # --- enable / disable toggles ---
  # Greenfield (default): everything true → create cluster + DB + DNS + blob +
  # vault + addons + realm. Consume mode: set enable_cluster /
  # enable_managed_postgres / enable_dns to false to consume cloud infra owned
  # by a separate "cloud substrate" Terraform; the stack then manages ONLY the
  # in-cluster and identity resources and reads the existing cluster by name.
  # See consume.tfvars.example.
  enable_cluster             = var.enable_cluster
  enable_managed_postgres    = var.enable_managed_postgres
  enable_dns                 = var.enable_dns
  enable_object_storage      = var.enable_object_storage
  enable_secrets_backend     = var.enable_secrets_backend
  enable_cache               = var.enable_cache
  enable_rwx_storage         = var.enable_rwx_storage
  enable_workload_namespaces = var.enable_workload_namespaces
  enable_ingress_tls         = var.enable_ingress_tls
  enable_identity_realm      = var.enable_identity_realm

  # --- consume-mode facts (existing cluster / server) ---
  cluster_name                     = var.cluster_name
  cluster_resource_group_name      = var.cluster_resource_group_name
  existing_vnet_id                 = var.existing_vnet_id
  existing_delegated_subnet_id     = var.existing_delegated_subnet_id
  existing_postgres_server_id      = var.existing_postgres_server_id
  existing_postgres_host           = var.existing_postgres_host
  existing_postgres_admin_login    = var.existing_postgres_admin_login
  existing_postgres_admin_password = var.existing_postgres_admin_password

  # --- provider credentials ---
  azure_subscription_id  = var.azure_subscription_id
  keycloak_url           = var.keycloak_url
  keycloak_client_id     = var.keycloak_client_id
  keycloak_client_secret = var.keycloak_client_secret
  keycloak_admin_realm   = var.keycloak_admin_realm

  # --- sizing + cluster ---
  azure_sizing       = var.azure_sizing
  kubernetes_version = var.kubernetes_version
  node_pools         = var.node_pools
  default_pool_id    = var.default_pool_id

  # --- postgres ---
  postgres_network_access        = var.postgres_network_access
  postgres_public_firewall_rules = var.postgres_public_firewall_rules
  # The database roster is YOURS: derive it from what you deploy. The stack has
  # no default and refuses to plan without it.
  platform_databases = var.platform_databases

  # --- workload namespaces ---
  # The namespace roster is YOURS too — full names, nothing derived.
  workload_namespaces = var.workload_namespaces

  # --- dns ---
  dns_records = var.dns_records

  # --- secrets backend ---
  key_vault_secrets = var.key_vault_secrets

  # --- ingress + tls ---
  acme_email                  = var.acme_email
  acme_server                 = var.acme_server
  tls_solver                  = var.tls_solver
  cluster_issuer_name         = var.cluster_issuer_name
  cluster_secret_store_name   = var.cluster_secret_store_name
  ingress_service_annotations = var.ingress_service_annotations

  # --- identity realm ---
  realm_display_name     = var.realm_display_name
  realm_clients          = var.realm_clients
  realm_roles            = var.realm_roles
  realm_protocol_mappers = var.realm_protocol_mappers

  # --- extension substrate claims ---
  extensions = var.extensions
}

output "substrate" {
  description = "The binding contract: non-secret facts a consumer binds to (docs/CONTRACTS.md § Binding contract)."
  value       = module.substrate.substrate
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL."
  value       = module.substrate.cluster_endpoint
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig YAML for the cluster."
  value       = module.substrate.kubeconfig_raw
  sensitive   = true
}

output "postgres_role_passwords" {
  description = "Generated passwords for the derived Postgres roles."
  value       = module.substrate.postgres_role_passwords
  sensitive   = true
}

# The two in-cluster names the consumer's own manifests reference — read from
# the stack (also in substrate.ingress.cluster_issuer_name /
# substrate.cluster_secret_store_name), never restated.
output "cluster_issuer_name" {
  description = "The ACME ClusterIssuer name for cert-manager.io/cluster-issuer; null when ingress is disabled."
  value       = module.substrate.cluster_issuer_name
}

output "cluster_secret_store_name" {
  description = "The ClusterSecretStore name for ExternalSecret secretStoreRef.name; null when ingress or the secrets backend is disabled."
  value       = module.substrate.cluster_secret_store_name
}

output "dns_name_servers" {
  description = "Delegate the apex to these at the registrar."
  value       = module.substrate.dns_name_servers
}

output "realm_id" {
  description = "The managed Keycloak realm id."
  value       = module.substrate.realm_id
}

output "extension_buckets" {
  description = "Extension-claimed storage account names keyed by \"<extension>/<claim>\"."
  value       = module.substrate.extension_buckets
}
