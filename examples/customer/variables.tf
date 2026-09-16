# Inputs of the minimal customer root — each passes straight through to the
# stack (stacks/digitalocean/xema-substrate/variables.tf has the full text).
# Every stack input not listed here keeps the stack's default; add one here
# the day you need to set it, never by forking the stack.

variable "do_token" {
  description = "DigitalOcean API token. Supply as TF_VAR_do_token."
  type        = string
  sensitive   = true
}

variable "keycloak_url" {
  description = "Base URL of the Keycloak server that will host the realm (the server is yours; the stack manages only the realm)."
  type        = string
}

variable "keycloak_client_id" {
  description = "Keycloak admin client id for the client-credentials grant."
  type        = string
}

variable "keycloak_client_secret" {
  description = "Keycloak admin client secret. Supply as TF_VAR_keycloak_client_secret."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region slug."
  type        = string
}

variable "tags" {
  description = "Tags applied to the cluster and database."
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "DOKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "DOKS control-plane version slug prefix (e.g. \"1.31.\")."
  type        = string
  default     = "1.31."
}

variable "node_pools" {
  description = "Node pools keyed by a stable pool id."
  type = map(object({
    size       = string
    node_count = number
    min_nodes  = optional(number)
    max_nodes  = optional(number)
    labels     = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}

variable "default_pool_id" {
  description = "Which key in node_pools is the DOKS default pool."
  type        = string
}

variable "postgres_name" {
  description = "Managed Postgres cluster name."
  type        = string
}

variable "postgres_engine_version" {
  description = "Major Postgres version (e.g. \"16\")."
  type        = string
  default     = "16"
}

variable "postgres_size" {
  description = "DO managed-database size slug."
  type        = string
}

variable "platform_databases" {
  description = "REQUIRED. Logical databases to ensure, verbatim — derive from what you deploy (the deployment root's bootstrap/postgres-databases.sql lists them)."
  type        = set(string)
}

variable "workload_namespaces" {
  description = "REQUIRED. Namespaces to ensure exist, by full name — derive from what you deploy."
  type        = set(string)
}

variable "dns_domain" {
  description = "Managed DNS zone apex."
  type        = string
}

variable "dns_records" {
  description = "DNS records keyed by a stable id."
  type = map(object({
    name  = string
    type  = optional(string, "A")
    value = string
    ttl   = optional(number, 300)
  }))
  default = {}
}

variable "realm_name" {
  description = "The one Keycloak realm this deployment owns. Never \"master\"."
  type        = string
}

variable "realm_display_name" {
  description = "Human-readable realm display name."
  type        = string
  default     = ""
}

variable "realm_access_token_lifespan" {
  description = "Access-token lifespan as a Go duration (e.g. \"5m\"). Set it: empty inherits Keycloak's default rather than deciding."
  type        = string
  default     = "5m"
}

variable "realm_clients" {
  description = "OpenID clients keyed by a stable id. BIND expects the identity-api client under the key `identity-api` (or pass --identity-client)."
  type = map(object({
    client_id                = string
    access_type              = string
    standard_flow_enabled    = optional(bool, true)
    service_accounts_enabled = optional(bool, false)
    valid_redirect_uris      = optional(list(string), [])
    web_origins              = optional(list(string), [])
    name                     = optional(string, "")
  }))
}

variable "realm_roles" {
  description = "Realm-level roles to create."
  type        = set(string)
  default     = []
}
