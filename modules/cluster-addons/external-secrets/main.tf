# The External Secrets Operator and the ONE ClusterSecretStore every ExternalSecret references.
#
# Its own add-on — not part of the ingress one — because a deployment needs its secrets from the
# first workload on, whatever serves its inbound traffic (an ingress controller this module set
# installs, a cloud provider's managed one, or none yet).

locals {
  external_secrets_values = yamlencode({
    serviceAccount = merge(
      { name = var.service_account_name },
      var.secret_store_backend == "azure-key-vault" && var.azure_key_vault_store != null ? {
        annotations = {
          "azure.workload.identity/client-id" = var.azure_key_vault_store.client_id
          "azure.workload.identity/tenant-id" = var.azure_key_vault_store.tenant_id
        }
      } : {},
    )
    podLabels = { "azure.workload.identity/use" = "true" }
  })

  secret_store_values = yamlencode({
    clusterSecretStore = {
      enabled = true
      name    = var.cluster_secret_store_name
      backend = var.secret_store_backend
      serviceAccount = {
        name      = var.service_account_name
        namespace = var.namespace
      }
      azureKeyVault = var.azure_key_vault_store != null ? {
        vaultUrl = var.azure_key_vault_store.vault_uri
      } : null
    }
  })
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  values = concat([local.external_secrets_values], var.values)

  lifecycle {
    precondition {
      condition     = var.secret_store_backend != "azure-key-vault" || var.azure_key_vault_store != null
      error_message = "secret_store_backend = \"azure-key-vault\" requires azure_key_vault_store (vault_uri, client_id, tenant_id)."
    }
  }
}

# The ClusterSecretStore is a custom resource whose CRD does not exist until the release above is
# installed, so it ships as a tiny LOCAL chart rather than kubernetes_manifest — which needs the CRD
# at PLAN time and therefore cannot survive a first apply on a fresh cluster.
resource "helm_release" "secret_store" {
  name      = "external-secrets-store"
  chart     = "${path.module}/charts/secret-store"
  namespace = var.namespace

  values = [local.secret_store_values]

  depends_on = [helm_release.external_secrets]
}
