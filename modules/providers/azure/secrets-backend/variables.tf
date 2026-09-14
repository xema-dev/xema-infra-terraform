variable "name" {
  description = "Key Vault name: 3-24 chars, letters/digits/hyphens, starting with a letter, globally unique as <name>.vault.azure.net."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z](?:[a-zA-Z0-9-]{1,22})[a-zA-Z0-9]$", var.name)) && !can(regex("--", var.name))
    error_message = "name must be 3-24 letters, digits or hyphens, start with a letter, end alphanumeric, and contain no consecutive hyphens."
  }
}

variable "region" {
  description = "Azure location (e.g. \"westeurope\")."
  type        = string
}

variable "secret_names" {
  description = "Secrets to SEED at provisioning time, by name (Key Vault secret names: letters, digits, hyphens). Each must have a value in secret_values."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.secret_names : can(regex("^[a-zA-Z0-9-]{1,127}$", n))])
    error_message = "Each secret name must be 1-127 letters, digits or hyphens."
  }
}

variable "secret_values" {
  description = "Values for every name in secret_names, keyed by name. Deliberately has NO default: supply via TF_VAR_secret_values / a decrypted tfvars, never a committed file. A name without a value fails fast."
  type        = map(string)
  sensitive   = true
}

variable "workload_identity" {
  description = <<-EOT
    Federate the cluster's OIDC issuer to a user-assigned identity that may READ
    secrets (Key Vault Secrets User), for the External Secrets Operator's
    service account:
      - enabled                   : create the identity + federated credential
      - oidc_issuer_url           : the cluster's OIDC issuer (providers/azure/cluster output)
      - service_account_namespace : the operator's namespace (default "external-secrets")
      - service_account_name      : the operator's service account (default "external-secrets")
  EOT
  type = object({
    enabled                   = bool
    oidc_issuer_url           = string
    service_account_namespace = optional(string, "external-secrets")
    service_account_name      = optional(string, "external-secrets")
  })
  default = {
    enabled         = false
    oidc_issuer_url = ""
  }

  validation {
    condition     = !var.workload_identity.enabled || startswith(var.workload_identity.oidc_issuer_url, "https://")
    error_message = "workload_identity.oidc_issuer_url must be an https:// URL when enabled."
  }
}

variable "grant_deployer_secrets_officer" {
  description = "Grant the principal running Terraform \"Key Vault Secrets Officer\" on the vault so it can write the seeded secrets. Set false only if that principal already holds an equivalent role."
  type        = bool
  default     = true
}

variable "rbac_propagation_wait" {
  description = "How long to wait after granting the deployer role before writing secrets. Azure RBAC assignments are eventually consistent (documented as up to several minutes, usually seconds); this is the one place a timed wait is warranted — the alternative is a failed first apply and a manual retry."
  type        = string
  default     = "30s"
}

variable "purge_protection_enabled" {
  description = "Key Vault purge protection. Cannot be turned off once on, and makes the vault name unusable for the retention period after deletion — so default false; enable for production."
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "Soft-delete retention (7-90 days)."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the vault accepts (authenticated) traffic from the public internet. false requires a private endpoint, which this module does not create."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Existing resource group to create the vault in. Empty string creates a dedicated resource group named \"<name>-rg\"."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every created resource."
  type        = map(string)
  default     = {}
}
