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

variable "service_account_name" {
  description = "Operator service account name — the subject the secret store's workload identity is federated to."
  type        = string
  default     = "external-secrets"
}

variable "values" {
  description = "Extra inline Helm values for external-secrets, merged AFTER the module's own. Each entry is a YAML document string."
  type        = list(string)
  default     = []
}

variable "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore ExternalSecret resources reference (secretStoreRef.name). A DNS-1123 subdomain name, as Kubernetes requires of the object."
  type        = string
  default     = "platform"

  validation {
    condition     = length(var.cluster_secret_store_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.cluster_secret_store_name))
    error_message = "cluster_secret_store_name must be a DNS-1123 subdomain name: lowercase letters, digits, hyphens and dots, starting and ending alphanumeric, at most 253 chars."
  }
}

variable "secret_store_backend" {
  description = "Which cloud secret store the ClusterSecretStore points at. Closed set; today only \"azure-key-vault\". Requires the matching *_store input."
  type        = string
  default     = "azure-key-vault"

  validation {
    condition     = contains(["azure-key-vault"], var.secret_store_backend)
    error_message = "secret_store_backend must be one of azure-key-vault."
  }
}

variable "azure_key_vault_store" {
  description = <<-EOT
    Azure Key Vault settings for the ClusterSecretStore (secret_store_backend =
    "azure-key-vault", authType WorkloadIdentity):
      - vault_uri : https://<name>.vault.azure.net/
      - client_id : client id of the reader identity federated to the operator's
                    service account (providers/azure/secrets-backend output client_id)
      - tenant_id : Entra tenant of that identity
  EOT
  type = object({
    vault_uri = string
    client_id = string
    tenant_id = string
  })
  default = null
}
