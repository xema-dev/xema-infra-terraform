terraform {
  required_version = ">= 1.6"

  # Remote state in a PRIVATE DigitalOcean Spaces bucket (S3-compatible).
  # Backend config is partial: the bucket/key/endpoint live in backend.hcl, NOT
  # here (that file holds deployment-specific values and is git-ignored). Init with:
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example for the shape.
  backend "s3" {}
}

module "substrate" {
  source = "../../stacks/digitalocean/xema-substrate"

  # --- enable / disable toggles ---
  # Greenfield (default): everything true → create cluster + DB + DNS + addons +
  # realm. Consume mode: set enable_cluster/enable_managed_postgres/enable_dns to
  # false to consume cloud infra owned by a separate "cloud substrate" Terraform;
  # the stack then manages ONLY the in-cluster and identity resources and reads
  # the existing cluster by name. See consume.tfvars.example.
  enable_cluster             = var.enable_cluster
  enable_managed_postgres    = var.enable_managed_postgres
  enable_dns                 = var.enable_dns
  enable_rwx_storage         = var.enable_rwx_storage
  enable_workload_namespaces = var.enable_workload_namespaces
  enable_identity_realm      = var.enable_identity_realm

  # Provider id of an existing managed-Postgres cluster to host extension
  # databases when enable_managed_postgres = false (consume mode).
  existing_database_cluster_id = var.existing_database_cluster_id

  # --- provider credentials ---
  do_token               = var.do_token
  do_spaces_access_id    = var.do_spaces_access_id
  do_spaces_secret_key   = var.do_spaces_secret_key
  keycloak_url           = var.keycloak_url
  keycloak_client_id     = var.keycloak_client_id
  keycloak_client_secret = var.keycloak_client_secret
  keycloak_admin_realm   = var.keycloak_admin_realm

  # --- global placement ---
  region = var.region
  tags   = var.tags

  # --- cluster ---
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  node_pools         = var.node_pools
  default_pool_id    = var.default_pool_id
  vpc_id             = var.vpc_id

  # --- postgres ---
  postgres_name           = var.postgres_name
  postgres_engine_version = var.postgres_engine_version
  postgres_size           = var.postgres_size
  # The database roster is YOURS: derive it from what you deploy. The stack has
  # no default and refuses to plan without it ([] when consuming a cluster).
  platform_databases = var.platform_databases
  postgres_roles     = var.postgres_roles

  # --- workload namespaces ---
  # The namespace roster is YOURS too. No default.
  workload_namespaces = var.workload_namespaces

  # --- dns ---
  dns_domain  = var.dns_domain
  dns_records = var.dns_records

  # --- identity realm ---
  realm_name             = var.realm_name
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

output "postgres_host" {
  description = "Managed Postgres host."
  value       = module.substrate.postgres_host
}

output "realm_id" {
  description = "The managed Keycloak realm id."
  value       = module.substrate.realm_id
}

output "extension_buckets" {
  description = "Extension-claimed bucket names keyed by \"<extension>/<claim>\"."
  value       = module.substrate.extension_buckets
}
