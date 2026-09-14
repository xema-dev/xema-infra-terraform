# Provider configuration lives ONLY at the stack/root level (never in the
# reusable modules). The kubernetes + helm providers target the cluster created
# by this stack (enable_cluster) OR an existing cluster read by name
# (data.azurerm_kubernetes_cluster.existing) — see locals.tf. This means the
# in-cluster addons work whether or not this stack owns the cluster.

# Authentication is the azurerm provider's own chain — `az login`, ARM_* env
# vars, a managed identity, or OIDC — never a credential in this configuration.
# subscription_id is required by azurerm; empty defers to ARM_SUBSCRIPTION_ID.
provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id != "" ? var.azure_subscription_id : null
}

# AKS hands out client-certificate credentials rather than a token, so the
# kube/helm providers authenticate with cert + key (see providers/azure/cluster).
provider "kubernetes" {
  host                   = local.kube_host
  client_certificate     = local.kube_client_cert_b64 != null ? base64decode(local.kube_client_cert_b64) : null
  client_key             = local.kube_client_key_b64 != null ? base64decode(local.kube_client_key_b64) : null
  cluster_ca_certificate = local.kube_ca_b64 != null ? base64decode(local.kube_ca_b64) : null
}

provider "helm" {
  kubernetes = {
    host                   = local.kube_host
    client_certificate     = local.kube_client_cert_b64 != null ? base64decode(local.kube_client_cert_b64) : null
    client_key             = local.kube_client_key_b64 != null ? base64decode(local.kube_client_key_b64) : null
    cluster_ca_certificate = local.kube_ca_b64 != null ? base64decode(local.kube_ca_b64) : null
  }
}

# Roles and grants live INSIDE the Postgres server (Azure has no logical-role
# API), so this provider targets the created server's admin credentials, or the
# existing server's when consuming. It connects lazily — only when a postgresql_*
# resource is in scope — so a deployment with no roles to manage needs nothing.
# The Azure admin is not a superuser: superuser = false is load-bearing.
provider "postgresql" {
  host      = local.pg_host
  port      = 5432
  username  = local.pg_admin_login
  password  = local.pg_admin_password
  database  = "postgres"
  sslmode   = "require"
  superuser = false
}

# Keycloak admin access via the client-credentials (service-account) grant. The
# identity-realm module is scoped to a single realm and never touches master.
provider "keycloak" {
  url           = var.keycloak_url
  client_id     = var.keycloak_client_id
  client_secret = var.keycloak_client_secret
  realm         = var.keycloak_admin_realm

  # Defer the admin login until a Keycloak resource is actually read/planned, so
  # operations that touch only cloud/in-cluster resources don't require Keycloak
  # credentials. Auth still fires — and fails fast — the moment an identity-realm
  # resource is in scope.
  initial_login = false
}
