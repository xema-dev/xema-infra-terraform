locals {
  dns01 = var.tls_solver == "dns01-azure"

  ingress_values = yamlencode({
    controller = {
      replicaCount = var.ingress_replica_count
      ingressClassResource = {
        name    = var.ingress_class_name
        default = var.ingress_default_class
      }
      service = merge(
        {
          type        = "LoadBalancer"
          annotations = var.ingress_service_annotations
        },
        var.ingress_load_balancer_ip != "" ? { loadBalancerIP = var.ingress_load_balancer_ip } : {},
      )
    }
  })

  # With dns01-azure the controller pod must carry the workload-identity label
  # so the Azure webhook injects the federated token cert-manager exchanges.
  cert_manager_values = yamlencode(merge(
    {
      crds = { enabled = true, keep = true }
      serviceAccount = {
        name = var.cert_manager_service_account_name
      }
    },
    local.dns01 ? {
      podLabels = { "azure.workload.identity/use" = "true" }
    } : {},
  ))

  external_secrets_values = yamlencode({
    serviceAccount = merge(
      { name = var.external_secrets_service_account_name },
      var.secret_store_backend == "azure-key-vault" && var.azure_key_vault_store != null ? {
        annotations = {
          "azure.workload.identity/client-id" = var.azure_key_vault_store.client_id
          "azure.workload.identity/tenant-id" = var.azure_key_vault_store.tenant_id
        }
      } : {},
    )
    podLabels = { "azure.workload.identity/use" = "true" }
  })

  cluster_config_values = yamlencode({
    clusterIssuer = {
      name             = var.cluster_issuer_name
      email            = var.acme_email
      server           = var.acme_server
      solver           = var.tls_solver
      ingressClassName = var.ingress_class_name
      dns01Azure = local.dns01 ? {
        subscriptionID    = var.dns01_azure.subscription_id
        resourceGroupName = var.dns01_azure.resource_group_name
        hostedZoneName    = var.dns01_azure.hosted_zone_name
        clientID          = var.dns01_azure.client_id
        environment       = var.dns01_azure.environment
      } : null
    }
    clusterSecretStore = {
      enabled = var.external_secrets_enabled
      name    = var.cluster_secret_store_name
      backend = var.secret_store_backend
      serviceAccount = {
        name      = var.external_secrets_service_account_name
        namespace = var.external_secrets_namespace
      }
      azureKeyVault = var.azure_key_vault_store != null ? {
        vaultUrl = var.azure_key_vault_store.vault_uri
      } : null
    }
  })
}

resource "helm_release" "ingress_nginx" {
  name             = var.ingress_nginx_release_name
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  namespace        = var.ingress_nginx_namespace
  create_namespace = true

  values = concat([local.ingress_values], var.ingress_nginx_values)
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  namespace        = var.cert_manager_namespace
  create_namespace = true

  values = concat([local.cert_manager_values], var.cert_manager_values)

  lifecycle {
    precondition {
      condition     = !local.dns01 || var.dns01_azure != null
      error_message = "tls_solver = \"dns01-azure\" requires dns01_azure (subscription, resource group, zone, client id)."
    }
  }
}

resource "helm_release" "external_secrets" {
  count = var.external_secrets_enabled ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = var.external_secrets_namespace
  create_namespace = true

  values = concat([local.external_secrets_values], var.external_secrets_values)

  lifecycle {
    precondition {
      condition     = var.secret_store_backend != "azure-key-vault" || var.azure_key_vault_store != null
      error_message = "secret_store_backend = \"azure-key-vault\" requires azure_key_vault_store (vault_uri, client_id, tenant_id)."
    }
  }
}

# The ClusterIssuer and ClusterSecretStore are custom resources whose CRDs do
# not exist until the two releases above are installed, so they ship as a tiny
# LOCAL chart rather than kubernetes_manifest — which needs the CRD at PLAN
# time and therefore cannot survive a first apply on a fresh cluster. Helm
# validates them at install, when the CRDs and their webhooks are up.
resource "helm_release" "cluster_config" {
  name      = "ingress-tls-cluster-config"
  chart     = "${path.module}/charts/cluster-config"
  namespace = var.cert_manager_namespace

  values = [local.cluster_config_values]

  depends_on = [helm_release.cert_manager, helm_release.external_secrets]
}
