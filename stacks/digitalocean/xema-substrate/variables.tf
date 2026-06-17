# ---------------------------------------------------------------------------
# Enable / disable toggles
# ---------------------------------------------------------------------------
# Each area of the substrate can be independently enabled or disabled. This lets
# one deployment manage ONLY its xema-specific resources (namespaces, RWX
# storage, identity realm, extension claims) while a SEPARATE "cloud substrate"
# Terraform owns the shared cloud infra (cluster, managed database, DNS zone).
# When a cloud module is disabled, the stack CONSUMES the existing resource
# instead of creating it (e.g. it reads the cluster by name for the kubernetes
# provider, and creates extension databases against existing_database_cluster_id).

variable "enable_cluster" {
  description = "Create the DOKS cluster. Set false to consume an existing cluster (read by var.cluster_name) — cloud infra owned by a separate Terraform."
  type        = bool
  default     = true
}

variable "enable_managed_postgres" {
  description = "Create the managed Postgres cluster. Set false to consume an existing one (extension databases target var.existing_database_cluster_id)."
  type        = bool
  default     = true
}

variable "enable_dns" {
  description = "Manage the DNS zone + records in this cloud. Set false when DNS is managed elsewhere."
  type        = bool
  default     = true
}

variable "enable_rwx_storage" {
  description = "Install the ReadWriteMany StorageClass + NFS provisioner on the (created or existing) cluster."
  type        = bool
  default     = true
}

variable "enable_workload_namespaces" {
  description = "Ensure the workload namespaces exist on the (created or existing) cluster."
  type        = bool
  default     = true
}

variable "enable_identity_realm" {
  description = "Manage the Keycloak realm (realm + clients + roles + mappers)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Provider credentials
# ---------------------------------------------------------------------------

variable "do_token" {
  description = "DigitalOcean API token used to manage/read the cluster, database, DNS, and Spaces buckets."
  type        = string
  sensitive   = true
}

variable "do_spaces_access_id" {
  description = "DigitalOcean Spaces access key id (S3-compatible). Required only when provisioning object buckets; empty leaves it unset."
  type        = string
  default     = ""
  sensitive   = true
}

variable "do_spaces_secret_key" {
  description = "DigitalOcean Spaces secret key (S3-compatible). Required only when provisioning object buckets; empty leaves it unset."
  type        = string
  default     = ""
  sensitive   = true
}

variable "keycloak_url" {
  description = "Base URL of the Keycloak server (e.g. \"https://id.example.com\"). Required only when enable_identity_realm = true."
  type        = string
  default     = ""
}

variable "keycloak_client_id" {
  description = "Keycloak admin client id for the client-credentials grant. Required only when enable_identity_realm = true."
  type        = string
  default     = ""
}

variable "keycloak_client_secret" {
  description = "Keycloak admin client secret for the client-credentials grant. Required only when enable_identity_realm = true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "keycloak_admin_realm" {
  description = "Realm the admin client authenticates against (typically \"master\"). The managed realm itself is set via var.realm_name."
  type        = string
  default     = "master"
}

# ---------------------------------------------------------------------------
# Global placement
# ---------------------------------------------------------------------------

variable "region" {
  description = "DigitalOcean region slug shared by the cluster, database, and buckets (e.g. \"fra1\")."
  type        = string
}

variable "tags" {
  description = "Tags applied to created cloud resources (cluster, database), keyed by tag name."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Cluster (modules/providers/digitalocean/cluster) — created when
# enable_cluster, otherwise read by name for the kubernetes/helm providers.
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "DOKS cluster name. Used to CREATE the cluster (enable_cluster) or to READ an existing one (for the in-cluster addons). Required whenever the cluster is created or any in-cluster module is enabled."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "DOKS control-plane version slug prefix (e.g. \"1.31.\"). Used only when creating the cluster."
  type        = string
  default     = "1.31."
}

variable "node_pools" {
  description = <<-EOT
    Node pools keyed by a stable pool id (used only when enable_cluster). Each:
      - size       : DO droplet slug (e.g. "s-4vcpu-8gb")
      - node_count : fixed node count when autoscaling is off
      - min_nodes  : enable autoscaling when set (with max_nodes)
      - max_nodes  : autoscaling upper bound
      - labels     : kubernetes node labels
      - taints     : node taints { key, value, effect }
  EOT
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
  description = "Existing VPC uuid for a created cluster/database. Empty lets DO pick the region default VPC."
  type        = string
  default     = ""
}

variable "cluster_auto_upgrade" {
  description = "Enable DOKS patch auto-upgrade (created cluster only)."
  type        = bool
  default     = false
}

variable "cluster_surge_upgrade" {
  description = "Enable DOKS surge upgrades (created cluster only)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Managed Postgres (modules/providers/digitalocean/managed-postgres) — created
# only when enable_managed_postgres.
# ---------------------------------------------------------------------------

variable "postgres_name" {
  description = "Managed Postgres cluster name (created cluster only)."
  type        = string
  default     = ""
}

variable "postgres_engine_version" {
  description = "Major Postgres version, e.g. \"16\" (created cluster only)."
  type        = string
  default     = ""
}

variable "postgres_size" {
  description = "DO managed-database size slug, e.g. \"db-s-1vcpu-2gb\" (created cluster only)."
  type        = string
  default     = ""
}

variable "postgres_node_count" {
  description = "Postgres node count (1 = single node, 2+ = primary plus standby replicas)."
  type        = number
  default     = 1

  validation {
    condition     = var.postgres_node_count >= 1
    error_message = "postgres_node_count must be >= 1."
  }
}

variable "postgres_databases" {
  description = "Base logical databases on the CREATED cluster. Leave empty when consuming a shared cluster (managing a subset there would plan to drop the rest)."
  type        = set(string)
  default     = []
}

variable "postgres_roles" {
  description = "Base logical roles on the CREATED cluster. Leave empty when consuming a shared cluster."
  type        = set(string)
  default     = []
}

variable "existing_database_cluster_id" {
  description = "Provider id of an existing managed-Postgres cluster to host extension-claimed dedicated databases when enable_managed_postgres = false."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# DNS (modules/providers/digitalocean/dns) — managed only when enable_dns.
# ---------------------------------------------------------------------------

variable "dns_domain" {
  description = "Managed DNS zone apex, e.g. \"example.com\" (used only when enable_dns)."
  type        = string
  default     = ""
}

variable "dns_records" {
  description = <<-EOT
    Base DNS records keyed by a stable id (used only when enable_dns). Extension
    records are merged on top automatically. Each record:
      - name  : record name relative to the zone apex ("@" for the apex)
      - type  : record type (default "A")
      - value : record value (CNAME values need a trailing dot)
      - ttl   : time-to-live in seconds (default 300)
  EOT
  type = map(object({
    name  = string
    type  = optional(string, "A")
    value = string
    ttl   = optional(number, 300)
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# RWX storage addon (modules/cluster-addons/rwx-storage)
# ---------------------------------------------------------------------------

variable "rwx_storage_class_name" {
  description = "Name of the ReadWriteMany StorageClass to create. Must match what the Helm app bring-up references."
  type        = string
  default     = "nfs-rwx-storage"
}

variable "rwx_chart_version" {
  description = "Pinned Helm chart version for the NFS provisioner. Empty installs the latest available."
  type        = string
  default     = ""
}

variable "rwx_is_default_class" {
  description = "Mark the RWX StorageClass as the cluster default."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Workload namespaces (modules/cluster-addons/workload-namespaces)
# ---------------------------------------------------------------------------

variable "workload_namespaces" {
  description = "Namespaces that must exist before the Helm application bring-up runs. Defaults to the canonical Xema set."
  type        = set(string)
  default = [
    "xema-prod",
    "shared-prod",
    "xema-infra",
    "xema-opencode-workers",
    "xema-biome-sidecars",
    "xema-biome-apis",
    "xema-image-builders",
  ]
}

variable "workload_namespace_labels" {
  description = "Optional per-namespace labels, keyed by namespace name."
  type        = map(map(string))
  default     = {}
}

# ---------------------------------------------------------------------------
# Identity realm (modules/identity-realm) — managed only when
# enable_identity_realm.
# ---------------------------------------------------------------------------

variable "realm_name" {
  description = "The single Keycloak realm this stack owns (e.g. \"xema-prod\"). Never \"master\". Required when enable_identity_realm."
  type        = string
  default     = ""

  validation {
    condition     = var.realm_name != "master"
    error_message = "realm_name must not be \"master\"."
  }
}

variable "realm_display_name" {
  description = "Human-readable realm display name shown on login screens."
  type        = string
  default     = ""
}

variable "realm_clients" {
  description = <<-EOT
    OpenID clients to create in the realm, keyed by a stable id. Each client:
      - client_id                : the OIDC client_id
      - access_type              : one of CONFIDENTIAL | PUBLIC | BEARER-ONLY
      - standard_flow_enabled    : enable the authorization-code flow
      - service_accounts_enabled : enable the client-credentials grant (CONFIDENTIAL only)
      - valid_redirect_uris      : allowed redirect URIs
      - web_origins              : allowed CORS web origins
      - name                     : optional human-readable name
  EOT
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
  description = <<-EOT
    Per-client user-attribute → token-claim protocol mappers, keyed by a stable
    id. Each mapper references a key in var.realm_clients via its `client` field.
  EOT
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

# ---------------------------------------------------------------------------
# Extension / biome substrate claims (see docs/extensions.md, extensions.tf)
# ---------------------------------------------------------------------------

variable "extensions" {
  description = <<-EOT
    Dedicated substrate claimed by biomes/extensions, keyed by extension id (the
    biome id). Each value carries any subset of a CLOSED set of three claim kinds:
      - object_buckets   : map(stable id => { name, acl?, versioning? })
      - managed_databases: map(stable id => { database, owner? })  (on the resolved cluster)
      - dns_records      : map(stable id => { name, type?, value, ttl? })  (requires enable_dns)
    Only declare a biome here when it needs a DEDICATED cloud resource the runtime
    biome installer cannot create. Shared-schema biomes need NO entry.
  EOT
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

  validation {
    condition = alltrue([
      for e in values(var.extensions) : alltrue([
        for b in values(e.object_buckets) : contains(["private", "public-read"], b.acl)
      ])
    ])
    error_message = "Each extension object_buckets acl must be one of private, public-read."
  }

  validation {
    condition = alltrue([
      for e in values(var.extensions) : alltrue([
        for r in values(e.dns_records) :
        contains(["A", "AAAA", "CNAME", "TXT", "MX", "NS", "SRV", "CAA", "SOA"], r.type)
      ])
    ])
    error_message = "Each extension dns_records type must be one of A, AAAA, CNAME, TXT, MX, NS, SRV, CAA, SOA."
  }
}
