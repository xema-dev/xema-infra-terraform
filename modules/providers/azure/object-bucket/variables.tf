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

variable "network_rules" {
  description = <<-EOT
    Opt-in VNet service-endpoint access: null (default) sets no rules. When
    set, the account denies by default, bypasses nothing, and admits only
    virtual_network_subnet_ids (full subnet resource ids). Needs
    public_network_access_enabled = true — service-endpoint rules are evaluated
    on the public endpoint — and each subnet must have the Microsoft.Storage
    service endpoint enabled by its owner (this module does not manage subnets).
  EOT
  type = object({
    virtual_network_subnet_ids = list(string)
  })
  default = null

  validation {
    condition     = var.network_rules == null || length(try(var.network_rules.virtual_network_subnet_ids, [])) > 0
    error_message = "network_rules.virtual_network_subnet_ids must name at least one subnet."
  }
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

variable "cors_rules" {
  description = <<-EOT
    Browser CORS rules, so presigned PUT/GET work straight from a web origin.
    Default [] sets none (today's behaviour). Each rule: allowed_origins ("*" or
    scheme://host[:port], no path), allowed_methods (upper-case, one of DELETE GET HEAD MERGE POST OPTIONS PUT PATCH),
    allowed_headers, exposed_headers and max_age (preflight cache, whole seconds).
    Azure: at most 5 rules, and allowed_headers and exposed_headers must each be
    non-empty (the azurerm provider requires at least one item; no placeholder is
    invented).
  EOT
  type = list(object({
    allowed_origins = list(string)
    allowed_methods = list(string)
    allowed_headers = optional(list(string), [])
    exposed_headers = optional(list(string), [])
    max_age         = optional(number, 0)
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.cors_rules : length(r.allowed_origins) > 0 && length(r.allowed_methods) > 0])
    error_message = "Each cors_rules entry needs at least one allowed_origins and one allowed_methods."
  }

  validation {
    condition     = alltrue([for r in var.cors_rules : alltrue([for o in r.allowed_origins : o == "*" || can(regex("^https?://[^/]+$", o))])])
    error_message = "Each cors_rules allowed_origins entry must be \"*\" or a scheme://host[:port] origin without a path (e.g. \"https://app.example.com\")."
  }

  validation {
    condition     = alltrue([for r in var.cors_rules : alltrue([for m in r.allowed_methods : contains(["DELETE", "GET", "HEAD", "MERGE", "POST", "OPTIONS", "PUT", "PATCH"], m)])])
    error_message = "Each cors_rules allowed_methods entry must be upper-case and one of DELETE GET HEAD MERGE POST OPTIONS PUT PATCH."
  }

  validation {
    condition     = alltrue([for r in var.cors_rules : r.max_age >= 0 && r.max_age == floor(r.max_age)])
    error_message = "cors_rules max_age must be a whole number of seconds >= 0."
  }

  validation {
    condition     = length(var.cors_rules) <= 5
    error_message = "Azure allows at most 5 CORS rules per storage service; cors_rules has more."
  }

  validation {
    condition     = alltrue([for r in var.cors_rules : length(r.allowed_headers) > 0 && length(r.exposed_headers) > 0])
    error_message = "On Azure each cors_rules entry needs a non-empty allowed_headers and exposed_headers: the azurerm provider requires at least one item in each (e.g. [\"*\"])."
  }
}
