# ---------------------------------------------------------------------------
# Deployment identity — everything else is DERIVED from these (see locals.tf)
# ---------------------------------------------------------------------------

variable "deployment_name" {
  description = <<-EOT
    The one name every resource, namespace, database and role derives from
    (e.g. "acme-dev"). 3-20 chars: lowercase letters, digits, single hyphens,
    starting with a letter and ending alphanumeric. The bound is what keeps
    every derived Azure name inside its limit (storage account "<compact>blob"
    <= 24, Key Vault "<name>-kv" <= 24). The ONE deterministic rewrite applied
    downstream is documented in locals.tf: Postgres identifiers replace "-"
    with "_" because an unquoted identifier cannot hold a hyphen.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.deployment_name)) && !can(regex("--", var.deployment_name))
    error_message = "deployment_name must be 3-20 chars of lowercase letters, digits and single hyphens, starting with a letter and ending alphanumeric."
  }
}

variable "environment" {
  description = "Deployment environment: one of \"dev\", \"prod\". Decides the irreversible safety knobs (Key Vault purge protection, backup retention) and lands on every resource as a tag."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of dev, prod."
  }
}

variable "region" {
  description = "Azure location shared by every created resource (e.g. \"westeurope\")."
  type        = string
}

variable "apex_domain" {
  description = "Public DNS zone apex the deployment's hostnames live under (e.g. \"example.com\"). Required when enable_dns; also the hosted zone for a dns01-azure solver."
  type        = string
  default     = ""

  validation {
    condition     = var.apex_domain == "" || can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", var.apex_domain))
    error_message = "apex_domain must be a bare domain name (e.g. example.com) or empty."
  }
}

variable "tags" {
  description = "Extra tags applied to every created cloud resource, merged over the derived { deployment, environment, managed-by } set."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Enable / disable toggles
# ---------------------------------------------------------------------------
# Each area of the substrate can be independently enabled or disabled. This lets
# one deployment manage ONLY its xema-specific resources (namespaces, RWX
# storage, identity realm, extension claims) while a SEPARATE "cloud substrate"
# Terraform owns the shared cloud infra. When a cloud module is disabled, the
# stack CONSUMES the existing resource instead of creating it.

variable "enable_cluster" {
  description = "Create the AKS cluster (+ VNet). Set false to consume an existing cluster, read by var.cluster_name / var.cluster_resource_group_name."
  type        = bool
  default     = true
}

variable "enable_managed_postgres" {
  description = "Create the PostgreSQL Flexible Server. Set false to consume an existing one (extension databases target var.existing_postgres_server_id)."
  type        = bool
  default     = true
}

variable "enable_dns" {
  description = "Manage the apex_domain DNS zone + records in Azure DNS. Set false when DNS is managed elsewhere."
  type        = bool
  default     = true
}

variable "enable_object_storage" {
  description = "Create the blob storage account the platform's blob-storage adapter targets."
  type        = bool
  default     = true
}

variable "enable_secrets_backend" {
  description = "Create the Key Vault + the External Secrets reader identity (and, with enable_ingress_tls, the operator + ClusterSecretStore)."
  type        = bool
  default     = true
}

variable "enable_cache" {
  description = "Create a managed Azure Cache for Redis. Off by default: the platform runs valkey in-cluster via Helm."
  type        = bool
  default     = false
}

variable "enable_rwx_storage" {
  description = "Create the ReadWriteMany StorageClass (Azure Files CSI, NFS) on the (created or existing) cluster."
  type        = bool
  default     = true
}

variable "enable_workload_namespaces" {
  description = "Ensure the derived workload namespaces exist on the (created or existing) cluster."
  type        = bool
  default     = true
}

variable "enable_ingress_tls" {
  description = "Install ingress-nginx, cert-manager + ClusterIssuer and External Secrets + ClusterSecretStore on the (created or existing) cluster."
  type        = bool
  default     = true
}

variable "enable_identity_realm" {
  description = "Manage the Keycloak realm (realm + clients + roles + mappers). Requires a reachable Keycloak (var.keycloak_url) — i.e. after the Helm bring-up."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Provider credentials
# ---------------------------------------------------------------------------

variable "azure_subscription_id" {
  description = "Azure subscription to deploy into. Empty defers to the ARM_SUBSCRIPTION_ID environment variable. Authentication itself always comes from the azurerm provider chain (az login / ARM_* / managed identity / OIDC)."
  type        = string
  default     = ""
}

variable "keycloak_url" {
  description = "Base URL of the Keycloak server (e.g. \"https://id.example.com\"). Required only when enable_identity_realm = true; echoed in the substrate output."
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
  description = "Realm the admin client authenticates against (typically \"master\"). The managed realm itself is derived from deployment_name."
  type        = string
  default     = "master"
}

# ---------------------------------------------------------------------------
# Sizing
# ---------------------------------------------------------------------------

variable "azure_sizing" {
  description = <<-EOT
    Azure SKU choices, all optional with small defaults:
      - aks_sku_tier          : "Free" | "Standard" | "Premium"
      - postgres_sku_name     : Flexible Server SKU (e.g. "B_Standard_B2s", "GP_Standard_D2ds_v5")
      - postgres_storage_mb   : provisioned storage in MB
      - postgres_ha           : zone-redundant HA (node_count 2)
      - blob_replication      : "LRS" | "ZRS" | "GRS" | "GZRS"
      - redis_sku             : "Basic" | "Standard" | "Premium" (enable_cache)
      - redis_capacity        : size step within the Redis SKU
  EOT
  type = object({
    aks_sku_tier        = optional(string, "Free")
    postgres_sku_name   = optional(string, "B_Standard_B2s")
    postgres_storage_mb = optional(number, 32768)
    postgres_ha         = optional(bool, false)
    blob_replication    = optional(string, "LRS")
    redis_sku           = optional(string, "Basic")
    redis_capacity      = optional(number, 1)
  })
  default = {}

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.azure_sizing.aks_sku_tier)
    error_message = "azure_sizing.aks_sku_tier must be one of Free, Standard, Premium."
  }

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.azure_sizing.blob_replication)
    error_message = "azure_sizing.blob_replication must be one of LRS, ZRS, GRS, GZRS."
  }

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.azure_sizing.redis_sku)
    error_message = "azure_sizing.redis_sku must be one of Basic, Standard, Premium."
  }
}

# ---------------------------------------------------------------------------
# Cluster (modules/providers/azure/cluster) — created when enable_cluster,
# otherwise read by name for the kubernetes/helm providers.
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "AKS cluster name. Empty derives \"<deployment_name>-aks\". Used to CREATE the cluster (enable_cluster) or to READ an existing one (consume mode)."
  type        = string
  default     = ""
}

variable "cluster_resource_group_name" {
  description = "Resource group of the cluster. Empty derives \"<deployment_name>-rg\" (created with the cluster in greenfield mode; must already exist in consume mode)."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "AKS control-plane version prefix (e.g. \"1.31\"). Used only when creating the cluster."
  type        = string
  default     = "1.31"
}

variable "node_pools" {
  description = <<-EOT
    Node pools keyed by a stable pool id — the key is also the AKS agent pool
    name (^[a-z][a-z0-9]{0,11}$). Used only when enable_cluster. Each:
      - size       : Azure VM size (e.g. "Standard_D4s_v5")
      - node_count : fixed node count when autoscaling is off
      - min_nodes  : enable autoscaling when set (with max_nodes)
      - max_nodes  : autoscaling upper bound
      - labels     : kubernetes node labels
      - taints     : node taints { key, value, effect } (not on the default pool)
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
  default = {
    generic = {
      size       = "Standard_D4s_v5"
      node_count = 3
    }
  }
}

variable "default_pool_id" {
  description = "Which key in node_pools is the AKS default (system) pool (used only when enable_cluster)."
  type        = string
  default     = "generic"
}

variable "cluster_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the Kubernetes API server (created cluster only). Empty leaves it unrestricted."
  type        = list(string)
  default     = []
}

variable "cluster_enable_log_analytics" {
  description = "Wire the created cluster's monitoring add-on to a Log Analytics workspace."
  type        = bool
  default     = false
}

variable "existing_vnet_id" {
  description = "Virtual network id to link the Postgres private DNS zone to when enable_cluster = false but enable_managed_postgres = true with private access."
  type        = string
  default     = ""
}

variable "existing_delegated_subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers, when enable_cluster = false but enable_managed_postgres = true with private access."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Managed Postgres (modules/providers/azure/managed-postgres) — created only
# when enable_managed_postgres. Databases and roles are DERIVED (locals.tf).
# ---------------------------------------------------------------------------

variable "postgres_engine_version" {
  description = "Major Postgres version (created server only)."
  type        = string
  default     = "16"
}

variable "postgres_network_access" {
  description = "How the created server is reached: \"private\" (VNet-injected through the cluster's delegated subnet) or \"public\" (public endpoint restricted to postgres_public_firewall_rules)."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public"], var.postgres_network_access)
    error_message = "postgres_network_access must be one of private, public."
  }
}

variable "postgres_public_firewall_rules" {
  description = "Firewall rules for a PUBLIC server, keyed by a stable id: { start_ip_address, end_ip_address }. Ignored when private."
  type = map(object({
    start_ip_address = string
    end_ip_address   = string
  }))
  default = {}
}

variable "postgres_administrator_password" {
  description = "Server administrator password. Empty generates one (kept in state, exposed as a sensitive output)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_billing_database" {
  description = "Also derive the \"<deployment>_billing_api\" database — billing is an edition decision, off by default."
  type        = bool
  default     = false
}

variable "postgres_extra_databases" {
  description = "Additional logical databases on the CREATED server, beyond the derived platform set. Unprefixed; use them as given."
  type        = set(string)
  default     = []
}

variable "existing_postgres_server_id" {
  description = "Resource id of an existing Flexible Server to host extension-claimed databases when enable_managed_postgres = false."
  type        = string
  default     = ""
}

variable "existing_postgres_host" {
  description = "FQDN of that existing server, for the postgresql provider (extension owner roles) when enable_managed_postgres = false."
  type        = string
  default     = ""
}

variable "existing_postgres_admin_login" {
  description = "Administrator login of the existing server (consume mode)."
  type        = string
  default     = ""
}

variable "existing_postgres_admin_password" {
  description = "Administrator password of the existing server (consume mode)."
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# DNS (modules/providers/azure/dns) — managed only when enable_dns.
# ---------------------------------------------------------------------------

variable "dns_records" {
  description = <<-EOT
    Base DNS records keyed by a stable id (used only when enable_dns). Extension
    records are merged on top automatically. Each record:
      - name  : record name relative to the zone apex ("@" for the apex, "*" wildcard)
      - type  : one of A, AAAA, CNAME, TXT (default "A")
      - value : record value
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
# Object storage (modules/providers/azure/object-bucket)
# ---------------------------------------------------------------------------

variable "blob_container_prefix" {
  description = "The BLOB_CONTAINER_PREFIX the platform composes container names from (\"<prefix>-<logical>\"). Empty derives deployment_name. Echoed in the substrate output for the Helm layer."
  type        = string
  default     = ""
}

variable "blob_containers" {
  description = "LOGICAL container names to pre-create as \"<blob_container_prefix>-<logical>\". Optional: the platform ensures its own containers at boot."
  type        = set(string)
  default     = []
}

variable "blob_versioning" {
  description = "Enable blob versioning on the storage account."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Secrets backend (modules/providers/azure/secrets-backend)
# ---------------------------------------------------------------------------

variable "key_vault_secrets" {
  description = <<-EOT
    Secrets to SEED into the Key Vault, keyed by secret name. An empty map seeds
    nothing (the default is an empty set, not a secret value). Supply real
    values via TF_VAR_key_vault_secrets / a decrypted tfvars, never a committed
    file.
  EOT
  type        = map(string)
  default     = {}
  # NOTE: not marked `sensitive` at the variable level — Terraform forbids
  # for_each over a sensitive value, and the secret NAMES must drive one. The
  # values are protected where it matters: they are passed to the module's
  # sensitive `secret_values` input, and azurerm_key_vault_secret.value is
  # sensitive in the provider schema, so they are redacted in plan output.
  # Same posture as cluster-addons/secrets.
}

# ---------------------------------------------------------------------------
# Ingress + TLS + External Secrets (modules/cluster-addons/ingress-tls)
# ---------------------------------------------------------------------------

variable "acme_email" {
  description = "ACME account contact e-mail. Required when enable_ingress_tls."
  type        = string
  default     = ""
}

variable "acme_server" {
  description = "ACME directory URL (Let's Encrypt production by default; use the staging directory while testing)."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "tls_solver" {
  description = "ACME challenge solver: \"http01\" or \"dns01-azure\" (needs enable_dns; required for wildcard certificates)."
  type        = string
  default     = "http01"

  validation {
    condition     = contains(["http01", "dns01-azure"], var.tls_solver)
    error_message = "tls_solver must be one of http01, dns01-azure."
  }
}

variable "ingress_service_annotations" {
  description = "Annotations on the ingress controller's LoadBalancer Service (e.g. \"service.beta.kubernetes.io/azure-dns-label-name\")."
  type        = map(string)
  default     = {}
}

variable "ingress_load_balancer_ip" {
  description = "Pin the ingress LoadBalancer to a pre-allocated static IP. Empty lets Azure assign one."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# RWX storage addon (modules/cluster-addons/rwx-storage) — Azure Files CSI
# ---------------------------------------------------------------------------

variable "rwx_storage_class_name" {
  description = "Name of the ReadWriteMany StorageClass to create. Kept equal to the DigitalOcean default so the Helm app bring-up references one name on every cloud."
  type        = string
  default     = "nfs-rwx-storage"
}

variable "rwx_storage_class_parameters" {
  description = "Parameters for the Azure Files CSI provisioner (file.csi.azure.com). The default provisions Premium NFS shares, the RWX profile with POSIX semantics."
  type        = map(string)
  default = {
    skuName  = "Premium_LRS"
    protocol = "nfs"
  }
}

variable "rwx_is_default_class" {
  description = "Mark the RWX StorageClass as the cluster default."
  type        = bool
  default     = false
}

variable "rwx_allow_volume_expansion" {
  description = "Whether PVCs bound to the RWX StorageClass may be expanded."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Workload namespaces (modules/cluster-addons/workload-namespaces) — DERIVED
# ---------------------------------------------------------------------------

variable "extra_workload_namespaces" {
  description = "Namespaces to ensure exist in addition to the derived set (locals.tf)."
  type        = set(string)
  default     = []
}

variable "workload_namespace_labels" {
  description = "Optional per-namespace labels, keyed by namespace name."
  type        = map(map(string))
  default     = {}
}

# ---------------------------------------------------------------------------
# Identity realm (modules/identity-realm) — managed only when
# enable_identity_realm. The realm NAME is derived (deployment_name).
# ---------------------------------------------------------------------------

variable "realm_display_name" {
  description = "Human-readable realm display name shown on login screens. Empty derives from deployment_name."
  type        = string
  default     = ""
}

variable "realm_access_token_lifespan" {
  description = "Access-token lifespan for the managed realm, as a Go duration string (e.g. \"5m\"). Empty keeps the Keycloak default; set it so the lifespan is intent."
  type        = string
  default     = ""
}

variable "realm_clients" {
  description = "OpenID clients to create in the realm, keyed by a stable id. See modules/identity-realm."
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
  description = "Per-client user-attribute → token-claim protocol mappers, keyed by a stable id. Each references a key in var.realm_clients via `client`."
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
      - object_buckets   : map(stable id => { name, acl?, versioning? })  (name = a storage account name)
      - managed_databases: map(stable id => { database, owner? })  (on the resolved server)
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
        for r in values(e.dns_records) : contains(["A", "AAAA", "CNAME", "TXT"], r.type)
      ])
    ])
    error_message = "Each extension dns_records type must be one of A, AAAA, CNAME, TXT."
  }
}
