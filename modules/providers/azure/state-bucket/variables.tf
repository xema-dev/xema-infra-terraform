variable "name" {
  description = "Storage account name dedicated to Terraform state: 3-24 lowercase letters/digits, globally unique across Azure."
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

variable "container_name" {
  description = "Blob container holding the state objects."
  type        = string
  default     = "tfstate"
}

variable "replication" {
  description = "Storage redundancy: one of \"LRS\", \"ZRS\", \"GRS\", \"GZRS\". State is small and precious; ZRS or GRS is a reasonable production choice."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication)
    error_message = "replication must be one of LRS, ZRS, GRS, GZRS."
  }
}

variable "soft_delete_retention_days" {
  description = "Days a deleted state blob (or blob version) stays recoverable."
  type        = number
  default     = 30

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "soft_delete_retention_days must be between 1 and 365."
  }
}

variable "shared_access_key_enabled" {
  description = "Allow account-key access (default true). false leaves Microsoft Entra ID as the only way in: every backend using this account must set use_azuread_auth = true and hold Storage Blob Data Contributor on it."
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
