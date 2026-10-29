variable "chart_version" {
  description = "Pinned external-secrets chart version (https://charts.external-secrets.io)."
  type        = string
  nullable    = false
  default     = "2.10.0"
}

variable "chart_repository" {
  description = "Helm repository of the external-secrets chart: an HTTPS repository or an oci:// registry path (e.g. oci://10.0.0.1/charts, holding the chart external-secrets). Override to pull from a private mirror."
  type        = string
  nullable    = false
  default     = "https://charts.external-secrets.io"

  validation {
    condition     = can(regex("^(https?|oci)://[^[:space:]]+$", var.chart_repository))
    error_message = "chart_repository must be an https://, http:// or oci:// URL."
  }
}

variable "namespace" {
  description = "Namespace the operator is installed into (created if absent)."
  type        = string
  default     = "external-secrets"
}

variable "values" {
  description = "Extra inline Helm values for external-secrets, merged AFTER the module's own. Each entry is a YAML document string."
  type        = list(string)
  default     = []
}

variable "secret_stores" {
  description = <<-EOT
    One entry per secret trust boundary, keyed by a boundary name of the caller's choosing.
    Each (boundary, namespace) gets its OWN user-assigned identity, federated to the store service
    account in that namespace and holding Key Vault Secrets User on ONLY the boundary's vault, plus
    a namespaced SecretStore in that namespace. Entries:
      - namespaces   : namespaces of the boundary (must already exist; no two entries share one)
      - key_vault_id : resource id of the boundary's Key Vault (no two entries share one)
      - vault_uri    : https://<name>.vault.azure.net/ of that vault
  EOT
  type = map(object({
    namespaces   = list(string)
    key_vault_id = string
    vault_uri    = string
  }))
  default = {}
}

variable "secret_store_name" {
  description = "Name of the namespaced SecretStore created in each boundary namespace (what ExternalSecret resources reference in secretStoreRef, kind SecretStore). A DNS-1123 subdomain name."
  type        = string
  default     = "platform"

  validation {
    condition     = length(var.secret_store_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.secret_store_name))
    error_message = "secret_store_name must be a DNS-1123 subdomain name: lowercase letters, digits, hyphens and dots, starting and ending alphanumeric, at most 253 chars."
  }
}

variable "store_service_account_name" {
  description = "Name of the service account created in each boundary namespace; the subject its identity is federated to."
  type        = string
  default     = "secret-store"
}

variable "identity_name_prefix" {
  description = "Prefix of each managed identity name (\"<prefix>-<boundary>-<namespace>\"): one identity per (boundary, namespace), because Azure refuses concurrent federated-credential writes on one identity and caps them at 20. Name length is validated (3-128), never truncated."
  type        = string
  default     = "eso"
}

variable "region" {
  description = "Azure location of the identities (e.g. \"westeurope\")."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group the identities are created in."
  type        = string
}

variable "oidc_issuer_url" {
  description = "The cluster's OIDC issuer URL (providers/azure/cluster output) the identities are federated to."
  type        = string

  validation {
    condition     = startswith(var.oidc_issuer_url, "https://")
    error_message = "oidc_issuer_url must be an https:// URL."
  }
}

variable "tags" {
  description = "Tags applied to every created Azure resource."
  type        = map(string)
  default     = {}
}

variable "known_namespaces" {
  description = "When set, the namespaces the caller creates; every boundary namespace must be one of them (the SecretStores are installed without creating their namespace). null skips the check, for namespaces owned elsewhere."
  type        = set(string)
  default     = null
}

variable "images" {
  description = <<-EOT
    Image overrides for the three External Secrets Operator images, keyed by component (`controller`, `webhook`, `cert_controller`); empty (the default) keeps the chart's own images.
    Each entry sets the full image repository (registry host and path, no tag or digest), a tag, and a REQUIRED
    sha256 digest, so a registry override can never be tags-only. Rendered into the chart as image.repository / image.tag (the chart has no digest key, so the tag value is `<tag>@<digest>`), webhook.image.* and certController.image.*. Leave the chart's `flavour` unset.
  EOT
  type = map(object({
    repository = string
    tag        = string
    digest     = string
  }))
  nullable = false
  default  = {}



}

variable "namespaces_ready" {
  description = "Opaque value the caller derives from the resources that create the boundary namespaces (e.g. their names). Only the in-cluster SecretStore releases wait for it; the Azure identities, federated credentials and role assignments depend on nothing in Kubernetes. null when the namespaces are owned elsewhere."
  type        = any
  default     = null
}
