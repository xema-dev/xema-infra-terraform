output "namespaces" {
  description = "Every namespace this identity is bound in (the deployment's plus `additional_namespaces`), created here or pre-existing."
  value       = local.namespaces
}

output "service_account_name" {
  description = "Name of the deployer ServiceAccount."
  value       = kubernetes_service_account_v1.deployer.metadata[0].name
}

output "token_secret_name" {
  description = "Name of the Secret holding the ServiceAccount token, in the deployment's namespace."
  value       = kubernetes_secret_v1.deployer_token.metadata[0].name
}

output "deployer_token" {
  description = "The ServiceAccount bearer token. A credential: route it to a secret store, never into a repository."
  value       = kubernetes_secret_v1.deployer_token.data["token"]
  sensitive   = true
}

output "deployer_kubeconfig" {
  description = <<-EOT
    A complete kubeconfig for the deployer ServiceAccount, ready for whatever
    runs `helm`/`kubectl` — the value a deployment's `kubeconfigRef` names.
    Null when `cluster_endpoint`/`cluster_ca_certificate_b64` were not supplied.

    A credential: `terraform output -raw deployer_kubeconfig` into a secret
    store. Rotating it is `taint` on the token Secret plus a re-bind; there is
    no long-lived cluster-admin credential anywhere in the chain.
  EOT
  value = local.emits_kubeconfig ? yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = var.context_name
      cluster = {
        server                       = var.cluster_endpoint
        "certificate-authority-data" = var.cluster_ca_certificate_b64
      }
    }]
    users = [{
      name = var.service_account_name
      user = { token = kubernetes_secret_v1.deployer_token.data["token"] }
    }]
    contexts = [{
      name = var.context_name
      context = {
        cluster   = var.context_name
        user      = var.service_account_name
        namespace = var.namespace
      }
    }]
    "current-context" = var.context_name
  }) : null
  sensitive = true
}

output "cluster_identity" {
  description = <<-EOT
    The three facts that identify a cluster no matter what anybody calls it:
    the API server endpoint, the sha256 of the DECODED cluster CA, and the UID
    of `kube-system`. A consumer recomputes all three from a flattened
    kubeconfig plus one `get namespace` and refuses to write if any differs.

    A context NAME is deliberately absent. It is an alias in a file, so the same
    cluster under a different alias is the same cluster, and a check that
    compares aliases refuses a correct target while admitting a wrong one that
    happens to share a name.

    `server` and `ca_certificate_sha256` are null when the cluster facts were
    not supplied; `kube_system_namespace_uid` is always read live.
  EOT
  value = {
    server                    = var.cluster_endpoint != "" ? var.cluster_endpoint : null
    ca_certificate_sha256     = local.ca_certificate_sha256
    kube_system_namespace_uid = data.kubernetes_namespace_v1.kube_system.metadata[0].uid
  }
}
