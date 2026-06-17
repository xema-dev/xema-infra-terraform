# Provider configuration lives ONLY at the stack/root level (never in the
# reusable modules). The kubernetes + helm providers target the cluster created
# by this stack (enable_cluster) OR an existing cluster read by name
# (data.digitalocean_kubernetes_cluster.existing) — see locals.tf. This means
# the in-cluster addons work whether or not this stack owns the cluster.

provider "digitalocean" {
  token = var.do_token

  # Spaces (S3-compatible) credentials, required for object-bucket operations
  # against DigitalOcean Spaces. Empty strings leave them unset so a deployment
  # that does not touch Spaces still plans/validates cleanly.
  spaces_access_id  = var.do_spaces_access_id != "" ? var.do_spaces_access_id : null
  spaces_secret_key = var.do_spaces_secret_key != "" ? var.do_spaces_secret_key : null
}

provider "kubernetes" {
  host                   = local.kube_host
  token                  = local.kube_token
  cluster_ca_certificate = local.kube_ca_b64 != null ? base64decode(local.kube_ca_b64) : null
}

provider "helm" {
  kubernetes = {
    host                   = local.kube_host
    token                  = local.kube_token
    cluster_ca_certificate = local.kube_ca_b64 != null ? base64decode(local.kube_ca_b64) : null
  }
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
