variable "name" {
  description = "Deployment name. Prefixes the resource group (when created), the VNet and the DNS-zone links."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}[a-z0-9]$", var.name))
    error_message = "name must be lower-case letters, digits and hyphens, 3-42 characters, starting with a letter."
  }
}

variable "region" {
  description = "Azure region of every resource this module creates."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the network in. Empty string creates a dedicated resource group named \"<name>-rg\"."
  type        = string
  default     = ""
}

variable "vnet_address_space" {
  description = "Address space of the virtual network."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_prefix" {
  description = "AKS node subnet (inside vnet_address_space)."
  type        = string
  default     = "10.0.0.0/20"
}

variable "postgres_subnet_prefix" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers (inside vnet_address_space)."
  type        = string
  default     = "10.0.16.0/24"
}

variable "private_endpoint_subnet_prefix" {
  description = "Subnet the private endpoints of the other backing services live in (inside vnet_address_space)."
  type        = string
  default     = "10.0.17.0/24"
}

variable "management_subnet_prefix" {
  description = "Subnet of the management runner (inside vnet_address_space). A /28 holds the runner with room to replace it."
  type        = string
  default     = "10.0.18.0/28"
}

variable "private_link_services" {
  description = "Private-link services this network hosts private endpoints for; one private DNS zone is created and linked per entry. Closed set: blob, redis, vault. Empty = no zones (every backing service public)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.private_link_services : contains(["blob", "redis", "vault"], s)])
    error_message = "private_link_services admits only blob, redis, vault."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}
