variable "name" {
  description = "Flexible Server name (3-63 chars, lowercase letters, digits, hyphens; globally unique as <name>.postgres.database.azure.com). Also the stem of the created resource group (\"<name>-rg\") when none is supplied."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 chars of lowercase letters, digits and hyphens, starting with a letter and ending alphanumeric."
  }
}

variable "region" {
  description = "Azure location (e.g. \"westeurope\")."
  type        = string
}

variable "engine_version" {
  description = "Major Postgres version (e.g. \"16\"). Maps to azurerm_postgresql_flexible_server.version."
  type        = string
}

variable "size" {
  description = "Flexible Server SKU name (e.g. \"B_Standard_B2s\", \"GP_Standard_D2ds_v5\")."
  type        = string
}

variable "node_count" {
  description = "1 = single zone; 2 = zone-redundant high availability with one standby. Azure has no N-replica flexible server, so nothing else is accepted."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2], var.node_count)
    error_message = "node_count must be 1 (single) or 2 (zone-redundant HA)."
  }
}

variable "vpc_id" {
  description = "Virtual network id to link the private DNS zone to (the network the clients live in). Required when network_access = \"private\"; ignored otherwise."
  type        = string
  default     = ""
}

variable "network_access" {
  description = "How the server is reached: \"private\" (VNet-injected via delegated_subnet_id + a private DNS zone; no public endpoint), \"private_endpoint\" (no public endpoint and no VNet injection; reached through a private endpoint composed by the caller, in a subnet that needs no delegation) or \"public\" (public endpoint restricted to public_firewall_rules)."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "private_endpoint", "public"], var.network_access)
    error_message = "network_access must be one of private, private_endpoint, public."
  }
}

variable "delegated_subnet_id" {
  description = "Id of a subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers (providers/azure/cluster exposes one as delegated_subnet_id). Required when network_access = \"private\"."
  type        = string
  default     = ""
}

variable "private_dns_zone_name" {
  description = "Name of the private DNS zone created for a private server. Must end in \".postgres.database.azure.com\". Empty derives \"<name>.private.postgres.database.azure.com\"."
  type        = string
  default     = ""

  validation {
    condition     = var.private_dns_zone_name == "" || endswith(var.private_dns_zone_name, ".postgres.database.azure.com")
    error_message = "private_dns_zone_name must end in .postgres.database.azure.com."
  }
}

variable "private_dns_zone_id" {
  description = "Id of an EXISTING private DNS zone for a private server, owned outside this module (e.g. by an enterprise landing zone's central DNS). Set, this module creates no zone and no VNet link — resolution is the zone owner's. Empty (default) creates the zone and links it to vpc_id."
  type        = string
  default     = ""
}

variable "public_firewall_rules" {
  description = "Firewall rules for a PUBLIC server, keyed by a stable id: { start_ip_address, end_ip_address }. Ignored when network_access = \"private\". An empty map on a public server means nobody can connect."
  type = map(object({
    start_ip_address = string
    end_ip_address   = string
  }))
  default = {}
}

variable "storage_mb" {
  description = "Provisioned storage in MB (Azure accepts fixed steps: 32768, 65536, 131072, …)."
  type        = number
  default     = 32768
}

variable "auto_grow_enabled" {
  description = "Let Azure grow storage automatically when it fills."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Backup retention in days (7-35)."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "geo_redundant_backup_enabled" {
  description = "Replicate backups to the paired region. Immutable after create."
  type        = bool
  default     = false
}

variable "zone" {
  description = "Availability zone for the primary (\"1\", \"2\", \"3\"). Empty lets Azure choose; the chosen zone is then ignore_changes'd so it never forces a replacement."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "1", "2", "3"], var.zone)
    error_message = "zone must be one of 1, 2, 3, or empty."
  }
}

variable "administrator_login" {
  description = "Server administrator login. Not a Postgres superuser on Azure — the postgresql provider must be configured with superuser = false."
  type        = string
  default     = "pgadmin"
}

variable "generate_administrator_password" {
  description = "Generate the administrator password with random_password (exposed as the sensitive administrator_password output and inside uri). Set false to supply administrator_password yourself. A boolean rather than \"empty means generate\" so a caller may pass a password that is itself unknown until apply."
  type        = bool
  default     = true
}

variable "administrator_password" {
  description = "Server administrator password, used when generate_administrator_password = false. Supply via TF_VAR_*, never committed."
  type        = string
  default     = ""
  sensitive   = true
}

variable "databases" {
  description = "Logical databases to ensure exist on the server."
  type        = set(string)
  default     = []
}

variable "database_owners" {
  description = "The role that OWNS each database, as `database => role` (both must be in `databases` / `roles`). The owner may CREATE in schema `public`, which on PostgreSQL 15+ no other role may — so the role an application migrates as must own its database. A database absent from the map is owned by the administrator."
  type        = map(string)
  default     = {}
}

variable "roles" {
  description = "Logical login roles to ensure exist on the server, created through the cyrilgdn/postgresql provider (modules/postgres-tenancy). Every role is granted CONNECT on every database in var.databases — CONNECT, TEMPORARY, CREATE on one it owns (database_owners); CONNECT is revoked from PUBLIC on each."
  type        = set(string)
  default     = []
}

variable "role_options" {
  description = "Optional per-role settings keyed by role name: create_database (CREATEDB), connection_limit (-1 = unlimited). A role absent from this map gets the defaults."
  type = map(object({
    create_database  = optional(bool, false)
    connection_limit = optional(number, -1)
  }))
  default = {}
}

variable "resource_group_name" {
  description = "Existing resource group to create the server in. Empty string creates a dedicated resource group named \"<name>-rg\"."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every created resource."
  type        = map(string)
  default     = {}
}
