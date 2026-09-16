# Pass-through variables for the DigitalOcean substrate example root. Each maps
# directly onto a stack input; see ../../stacks/digitalocean/xema-substrate for
# the full descriptions.
#
# Defaults mirror the stack's defaults so this root works in BOTH modes:
#   - greenfield (terraform.tfvars.example): create cluster + DB + DNS + addons + realm.
#   - consume    (consume.tfvars.example):   disable cloud infra, consume an existing
#                                            cluster by name + an existing DB cluster id.

# --- enable / disable toggles (all default true = greenfield) ---

variable "enable_cluster" {
  description = "Create the DOKS cluster. false ⇒ consume an existing one (read by cluster_name)."
  type        = bool
  default     = true
}

variable "enable_managed_postgres" {
  description = "Create the managed Postgres cluster. false ⇒ extension DBs target existing_database_cluster_id."
  type        = bool
  default     = true
}

variable "enable_dns" {
  description = "Manage the DNS zone + records. false ⇒ DNS owned elsewhere."
  type        = bool
  default     = true
}

variable "enable_rwx_storage" {
  description = "Install the RWX StorageClass + NFS provisioner on the (created or consumed) cluster."
  type        = bool
  default     = true
}

variable "enable_workload_namespaces" {
  description = "Ensure the workload namespaces exist on the (created or consumed) cluster."
  type        = bool
  default     = true
}

variable "enable_identity_realm" {
  description = "Manage the Keycloak realm (realm + clients + roles + mappers)."
  type        = bool
  default     = true
}

variable "existing_database_cluster_id" {
  description = "Provider id of an existing managed-Postgres cluster to host extension databases when enable_managed_postgres = false."
  type        = string
  default     = ""
}

variable "do_token" {
  description = "DigitalOcean API token."
  type        = string
  sensitive   = true
}

variable "do_spaces_access_id" {
  description = "DigitalOcean Spaces access key id (S3-compatible)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "do_spaces_secret_key" {
  description = "DigitalOcean Spaces secret key (S3-compatible)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "keycloak_url" {
  description = "Base URL of the Keycloak server. Required only when enable_identity_realm."
  type        = string
  default     = ""
}

variable "keycloak_client_id" {
  description = "Keycloak admin client id for the client-credentials grant. Required only when enable_identity_realm."
  type        = string
  default     = ""
}

variable "keycloak_client_secret" {
  description = "Keycloak admin client secret for the client-credentials grant. Required only when enable_identity_realm."
  type        = string
  sensitive   = true
  default     = ""
}

variable "keycloak_admin_realm" {
  description = "Realm the admin client authenticates against."
  type        = string
  default     = "master"
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
  description = "DOKS cluster name. Used to CREATE (enable_cluster) or READ an existing cluster (consume mode)."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "DOKS control-plane version slug prefix (e.g. \"1.31.\"). Used only when creating the cluster."
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
  default = {}
}

variable "default_pool_id" {
  description = "Which key in node_pools is the DOKS default pool (used only when enable_cluster)."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "Existing VPC uuid for the cluster and database. Empty lets DO pick the region default VPC."
  type        = string
  default     = ""
}

variable "postgres_name" {
  description = "Managed Postgres cluster name (created cluster only)."
  type        = string
  default     = ""
}

variable "postgres_engine_version" {
  description = "Major Postgres version (e.g. \"16\") (created cluster only)."
  type        = string
  default     = ""
}

variable "postgres_size" {
  description = "DO managed-database size slug (created cluster only)."
  type        = string
  default     = ""
}

variable "platform_databases" {
  description = "Logical databases to ensure on the created cluster, verbatim. Required — derive it from what you deploy; [] when consuming a shared cluster."
  type        = set(string)
}

variable "workload_namespaces" {
  description = "Namespaces to ensure exist, by full name. Required — derive it from what you deploy."
  type        = set(string)
}

variable "postgres_roles" {
  description = "Base set of logical roles to ensure exist."
  type        = set(string)
  default     = []
}

variable "dns_domain" {
  description = "Managed DNS zone apex (used only when enable_dns)."
  type        = string
  default     = ""
}

variable "dns_records" {
  description = "Base DNS records keyed by a stable id."
  type = map(object({
    name  = string
    type  = optional(string, "A")
    value = string
    ttl   = optional(number, 300)
  }))
  default = {}
}

variable "realm_name" {
  description = "The single Keycloak realm this deployment owns. Never \"master\". Required when enable_identity_realm."
  type        = string
  default     = ""

  validation {
    condition     = var.realm_name != "master"
    error_message = "realm_name must not be \"master\"."
  }
}

variable "realm_display_name" {
  description = "Human-readable realm display name."
  type        = string
  default     = ""
}

variable "realm_clients" {
  description = "OpenID clients to create in the realm, keyed by a stable id."
  type = map(object({
    client_id                = string
    access_type              = string
    standard_flow_enabled    = optional(bool, true)
    service_accounts_enabled = optional(bool, false)
    valid_redirect_uris      = optional(list(string), [])
    web_origins              = optional(list(string), [])
    name                     = optional(string, "")
  }))
  default = {}
}

variable "realm_roles" {
  description = "Realm-level roles to create."
  type        = set(string)
  default     = []
}

variable "realm_protocol_mappers" {
  description = "Per-client user-attribute → token-claim protocol mappers, keyed by a stable id."
  type = map(object({
    client              = string
    user_attribute      = string
    claim_name          = string
    claim_value_type    = optional(string, "String")
    name                = optional(string, "")
    add_to_id_token     = optional(bool, true)
    add_to_access_token = optional(bool, true)
    add_to_userinfo     = optional(bool, true)
    multivalued         = optional(bool, false)
  }))
  default = {}
}

variable "extensions" {
  description = "Dedicated out-of-cluster substrate claimed by extensions, keyed by extension id. See docs/extensions.md."
  type = map(object({
    object_buckets = optional(map(object({
      name       = string
      acl        = optional(string, "private")
      versioning = optional(bool, false)
    })), {})
    managed_databases = optional(map(object({
      database = string
      owner    = optional(string)
    })), {})
    dns_records = optional(map(object({
      name  = string
      type  = optional(string, "A")
      value = string
      ttl   = optional(number, 300)
    })), {})
  }))
  default = {}
}
