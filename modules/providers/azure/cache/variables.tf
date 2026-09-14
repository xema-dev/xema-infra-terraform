variable "name" {
  description = "Cache name (1-63 chars, letters/digits/hyphens; globally unique as <name>.redis.cache.windows.net)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$", var.name))
    error_message = "name must be 1-63 letters, digits or hyphens, starting and ending alphanumeric."
  }
}

variable "region" {
  description = "Azure location (e.g. \"westeurope\")."
  type        = string
}

variable "sku" {
  description = "Azure Cache for Redis SKU: one of \"Basic\", \"Standard\", \"Premium\". The family (C or P) is derived from it."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of Basic, Standard, Premium."
  }
}

variable "capacity" {
  description = "Size step within the SKU: 0-6 for Basic/Standard (C0-C6), 1-5 for Premium (P1-P5)."
  type        = number
  default     = 1

  validation {
    condition     = var.capacity >= 0 && var.capacity <= 6
    error_message = "capacity must be between 0 and 6."
  }
}

variable "redis_version" {
  description = "Redis major version offered by Azure (\"6\")."
  type        = string
  default     = "6"
}

variable "public_network_access_enabled" {
  description = "Whether the cache accepts traffic from the public internet (TLS + access key). false requires a private endpoint, which this module does not create."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Existing resource group to create the cache in. Empty string creates a dedicated resource group named \"<name>-rg\"."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every created resource."
  type        = map(string)
  default     = {}
}
