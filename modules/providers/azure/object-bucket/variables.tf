variable "name" {
  description = "Storage account name: 3-24 lowercase letters/digits, globally unique across Azure. This is the contract's \"bucket\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "name must be 3-24 lowercase letters or digits (an Azure storage account name)."
  }
}

variable "region" {
  description = "Azure location (e.g. \"westeurope\")."
  type        = string
}

variable "acl" {
  description = "Canned ACL: \"private\" (containers private, no anonymous access) or \"public-read\" (containers readable anonymously at blob level)."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public-read"], var.acl)
    error_message = "acl must be one of private, public-read."
  }
}

variable "versioning" {
  description = "Enable blob versioning on the account."
  type        = bool
  default     = false
}

variable "containers" {
  description = "Blob containers to pre-create. Optional: the platform's blob-storage module ensures its own \"<prefix>-<logical>\" containers at boot, so list containers here only when the runtime identity may not create them."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.containers : can(regex("^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$", c))])
    error_message = "Each container name must be 3-63 lowercase letters, digits or hyphens, starting and ending alphanumeric."
  }
}

variable "replication" {
  description = "Storage redundancy: one of \"LRS\", \"ZRS\", \"GRS\", \"GZRS\"."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication)
    error_message = "replication must be one of LRS, ZRS, GRS, GZRS."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the account's endpoints accept traffic from the public internet (authenticated; anonymous access is governed by acl). false requires a private endpoint: the stack composes one with providers/azure/private-endpoint (this module knows nothing about networks)."
  type        = bool
  default     = true
}

variable "shared_access_key_enabled" {
  description = "Allow account-key (shared key) authentication — what the platform's blob-storage adapter uses today. Disable only once every consumer authenticates with Entra identities."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Existing resource group to create the account in. Empty string creates a dedicated resource group named \"<name>-rg\"."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every created resource."
  type        = map(string)
  default     = {}
}
