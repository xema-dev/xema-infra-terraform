# The minimal CUSTOMER-OWNED consumer root.
#
# This is the whole of what a customer's private repository carries for the
# substrate: THIS file (a pinned module version + the outputs it binds), its
# variables, a tfvars file and a backend.hcl — never a forked stack. The stack
# is consumed by `?ref=` at one released version; adopting a new version is a
# one-line change here plus `terraform init -upgrade` and a reviewed plan.
#
# It is parameter-identical across the three ownership modes in
# docs/CONTRACTS.md § Three ownership modes: what differs between
# customer-operated, vendor-operated and vendor-hosted is who holds
# backend.hcl, the tfvars and the credentials — not one line of this file.

terraform {
  required_version = ">= 1.6"

  # Remote state in the customer's PRIVATE object-storage bucket. Partial
  # config: bucket / key / endpoint live in backend.hcl (git-ignored):
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}

module "substrate" {
  # Pin the RELEASED version. Never `main`, never a branch: a moving ref makes
  # `terraform init -upgrade` a change nobody reviewed.
  source = "git::https://github.com/xema-dev/xema-infra-terraform.git//stacks/digitalocean/xema-substrate?ref=v0.6.0"

  # --- provider credentials (TF_VAR_* in the environment, never in a file) ---
  do_token               = var.do_token
  keycloak_url           = var.keycloak_url
  keycloak_client_id     = var.keycloak_client_id
  keycloak_client_secret = var.keycloak_client_secret

  # --- placement ---
  region = var.region
  tags   = var.tags

  # --- cluster ---
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  node_pools         = var.node_pools
  default_pool_id    = var.default_pool_id

  # --- postgres ---
  postgres_name           = var.postgres_name
  postgres_engine_version = var.postgres_engine_version
  postgres_size           = var.postgres_size
  # The two REQUIRED rosters. Yours: derive them from what you deploy.
  platform_databases  = var.platform_databases
  workload_namespaces = var.workload_namespaces

  # --- dns ---
  dns_domain  = var.dns_domain
  dns_records = var.dns_records

  # --- identity realm ---
  realm_name                  = var.realm_name
  realm_display_name          = var.realm_display_name
  realm_access_token_lifespan = var.realm_access_token_lifespan
  realm_clients               = var.realm_clients
  realm_roles                 = var.realm_roles
}

# ── outputs: exactly what BIND reads (tooling/bind/README.md) ────────────────
# `terraform output -json | node tooling/bind/bind-outputs.mjs …` needs the
# binding map plus the sensitive outputs it routes; the rest are the operator's.

output "substrate" {
  description = "The binding contract: non-secret facts the deployment root binds to (docs/CONTRACTS.md § Binding contract)."
  value       = module.substrate.substrate
}

output "realm_client_secrets" {
  description = "Realm OIDC client secrets keyed by realm_clients key. BIND routes the identity-api client's to the externals file."
  value       = module.substrate.realm_client_secrets
  sensitive   = true
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig. An operator step: `terraform output -raw kubeconfig_raw`."
  value       = module.substrate.kubeconfig_raw
  sensitive   = true
}

output "postgres_uri" {
  description = "Admin connection URI. An operator step: runs the deployment root's database bootstrap."
  value       = module.substrate.postgres_uri
  sensitive   = true
}
