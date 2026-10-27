# The External Secrets Operator and one namespaced SecretStore per namespace of each secret trust
# boundary. There is NO cluster-wide store: a ClusterSecretStore reads one vault through one
# identity for every namespace, so any namespace could ExternalSecret any other's secrets. Here each
# (boundary, namespace) has its own identity, federated to the service account in THAT namespace
# only, with Key Vault Secrets User on ONLY the boundary's vault. The isolation rules (no shared namespace, no shared
# vault) are enforced by ./boundaries.
#
# Its own add-on — not part of the ingress one — because a deployment needs its secrets from the
# first workload on, whatever serves its inbound traffic.

module "boundaries" {
  source = "./boundaries"

  secret_stores        = var.secret_stores
  identity_name_prefix = var.identity_name_prefix
  known_namespaces     = var.known_namespaces
}

data "azurerm_client_config" "current" {}

locals {
  external_secrets_values = yamlencode({
    # Identity comes from each SecretStore's own service account, never from the operator's.
    serviceAccount = { name = "external-secrets" }
  })

  # Empty by default, so the rendered values are unchanged. The chart has no digest key: the tag
  # value carries "<tag>@<digest>" and the chart renders repository:tag.
  images_values = length(var.images) == 0 ? [] : [yamlencode(merge(
    { for k, v in var.images : "image" => { repository = v.repository, tag = "${v.tag}@${v.digest}" } if k == "controller" },
    { for k, v in var.images : (k == "webhook" ? "webhook" : "certController") => {
      image = { repository = v.repository, tag = "${v.tag}@${v.digest}" }
    } if k != "controller" },
  ))]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = var.chart_repository
  chart            = "external-secrets"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  values = concat([local.external_secrets_values], local.images_values, var.values)
}

# One identity per (boundary, namespace): Azure refuses concurrent federated-credential writes on a
# single identity and caps them at 20, so a shared per-boundary identity could not be applied in
# parallel. Each has exactly one credential and its role is scoped to the boundary's vault only.
resource "azurerm_user_assigned_identity" "store" {
  for_each = module.boundaries.stores

  name                = each.value.identity_name
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "store" {
  for_each = module.boundaries.stores

  name                      = var.store_service_account_name
  user_assigned_identity_id = azurerm_user_assigned_identity.store[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:${each.value.namespace}:${var.store_service_account_name}"
}

resource "azurerm_role_assignment" "store" {
  for_each = module.boundaries.stores

  scope                = each.value.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.store[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# SecretStore is a custom resource whose CRD does not exist until the release above is installed,
# so it ships as a tiny LOCAL chart rather than kubernetes_manifest — which needs the CRD at PLAN
# time and therefore cannot survive a first apply on a fresh cluster. One release per boundary
# namespace; the namespace must already exist.
resource "helm_release" "secret_store" {
  for_each = module.boundaries.stores

  name      = "external-secrets-store"
  chart     = "${path.module}/charts/secret-store"
  namespace = each.value.namespace

  values = [yamlencode({
    secretStore = {
      name = var.secret_store_name
      serviceAccount = {
        name     = var.store_service_account_name
        clientId = azurerm_user_assigned_identity.store[each.key].client_id
        tenantId = data.azurerm_client_config.current.tenant_id
      }
      azureKeyVault = { vaultUrl = each.value.vault_uri }
    }
  })]

  depends_on = [helm_release.external_secrets, azurerm_federated_identity_credential.store, azurerm_role_assignment.store]
}
