# The admin's own identity (`az login`); no credential in this configuration.
provider "azapi" {}

# Used only when apply_via = "in-vnet" (the API server is reachable). Entra RBAC
# with local accounts off: the provider execs kubelogin with the admin's az login.
# Unused, and never contacted, with apply_via = "run-command".
provider "helm" {
  kubernetes = {
    host                   = var.kube_host
    cluster_ca_certificate = var.kube_ca_b64 != null ? base64decode(var.kube_ca_b64) : null
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args        = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
    }
  }
}
