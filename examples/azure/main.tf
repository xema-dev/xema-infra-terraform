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

  # --- enable / disable toggles ---
  # Greenfield (default): everything true → create cluster + DB + DNS + blob +
  # vault + addons + realm. Consume mode: set enable_cluster /
  # enable_managed_postgres / enable_dns to false to consume cloud infra owned
  # by a separate "cloud substrate" Terraform; the stack then manages ONLY
  # xema-specific resources and reads the existing cluster by name. See
  # consume.tfvars.example.
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
  enable_billing_database        = var.enable_billing_database

  # --- dns ---
  dns_records = var.dns_records

  # --- secrets backend ---
  key_vault_secrets = var.key_vault_secrets

  # --- ingress + tls ---
  acme_email                  = var.acme_email
  acme_server                 = var.acme_server
  tls_solver                  = var.tls_solver
  ingress_service_annotations = var.ingress_service_annotations

  # --- identity realm ---
  realm_display_name     = var.realm_display_name
  realm_clients          = var.realm_clients
  realm_roles            = var.realm_roles
  realm_protocol_mappers = var.realm_protocol_mappers

  # --- extension / biome substrate claims ---
  extensions = var.extensions
}

output "substrate" {
  description = "Non-secret facts the Helm layer consumes."
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

output "dns_name_servers" {
  description = "Delegate the apex to these at the registrar."
  value       = module.substrate.dns_name_servers
}

output "realm_id" {
  description = "The managed Keycloak realm id."
  value       = module.substrate.realm_id
}

output "extension_buckets" {
  description = "Extension-claimed storage account names keyed by \"<biome>/<claim>\"."
  value       = module.substrate.extension_buckets
}
