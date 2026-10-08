variable "secret_stores" {
  description = <<-EOT
    One entry per secret trust boundary, keyed by a boundary name of the caller's choosing (a
    Xema deployment, the infrastructure authority, a shared deployment, ...). Each entry:
      - namespaces   : the namespaces that boundary's workloads run in; each gets its own
                       namespaced SecretStore
      - key_vault_id : resource id of the ONE Key Vault that boundary may read
      - vault_uri    : https://<name>.vault.azure.net/ of that vault
    No two entries may share a namespace or a key vault: that is what keeps one boundary from
    reading another's secrets.
  EOT
  type = map(object({
    namespaces   = list(string)
    key_vault_id = string
    vault_uri    = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, _ in var.secret_stores : can(regex("^[a-z0-9]([-a-z0-9]{0,38}[a-z0-9])?$", k))])
    error_message = "Each secret_stores key must be 1-40 lowercase letters, digits or hyphens, starting and ending alphanumeric."
  }

  validation {
    condition     = alltrue([for _, s in var.secret_stores : length(s.namespaces) > 0])
    error_message = "Each secret_stores entry needs at least one namespace."
  }

  validation {
    condition     = alltrue([for _, s in var.secret_stores : alltrue([for ns in s.namespaces : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", ns))])])
    error_message = "Each namespace must be a DNS-1123 label (1-63 lowercase alphanumerics or hyphens, starting and ending alphanumeric)."
  }

  validation {
    condition = (
      length(flatten([for _, s in var.secret_stores : s.namespaces])) ==
      length(distinct(flatten([for _, s in var.secret_stores : s.namespaces])))
    )
    error_message = "A namespace may appear in only one secret_stores entry (and once within it): a namespace shared by two boundaries would let one read the other's vault."
  }

  validation {
    condition = (
      length([for _, s in var.secret_stores : lower(s.key_vault_id)]) ==
      length(distinct([for _, s in var.secret_stores : lower(s.key_vault_id)]))
    )
    error_message = "Two secret_stores entries may not share a key_vault_id: a shared vault is readable by both identities, so the boundary between them is gone."
  }

  validation {
    condition     = alltrue([for _, s in var.secret_stores : startswith(s.vault_uri, "https://") && s.key_vault_id != ""])
    error_message = "Each secret_stores entry needs a key_vault_id and an https:// vault_uri."
  }
}

variable "identity_name_prefix" {
  description = "Prefix of each store's managed identity name (\"<prefix>-<boundary>-<namespace>\"). The name must fit Azure's 3-128 limit; it is refused, never truncated."
  type        = string
  default     = "eso"
}

variable "known_namespaces" {
  description = "When set, the namespaces that exist or are created alongside; every boundary namespace must be one of them (a SecretStore is installed without creating its namespace). null skips the check, for namespaces owned elsewhere."
  type        = set(string)
  default     = null
}
