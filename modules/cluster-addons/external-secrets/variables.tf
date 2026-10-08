variable "chart_version" {
  description = "Pinned external-secrets chart version (https://charts.external-secrets.io)."
  type        = string
  default     = "2.10.0"
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
    Each boundary gets its OWN user-assigned identity, federated to a service account in each of
    its namespaces and holding Key Vault Secrets User on ONLY its own vault, plus a namespaced
    SecretStore in each of those namespaces. Entries:
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
  description = "Prefix of each boundary's managed identity name (\"<prefix>-<boundary>\")."
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
