# ---------------------------------------------------------------------------
# Deployment identity — everything else is DERIVED from these (see locals.tf)
# ---------------------------------------------------------------------------

variable "deployment_name" {
  description = <<-EOT
    The one name every resource, namespace, database and role derives from
    (e.g. "acme-dev"). 3-20 chars: lowercase letters, digits, single hyphens,
    starting with a letter and ending alphanumeric. The bound is what keeps
    every derived Azure name inside its limit (storage account "<compact>blob"
    <= 24, Key Vault "<name>-kv" <= 24). The four globally-unique derived
    names each take an optional override (key_vault_name, storage_account_name,
    postgres_server_name, redis_cache_name). The ONE deterministic rewrite applied
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
# Overrides for the GLOBALLY-UNIQUE derived names.
#
# Four Azure names are unique across every tenant, not just this one, because
# each is a public DNS label: the Key Vault (<name>.vault.azure.net), the
# storage account (<name>.blob.core.windows.net), the Flexible Server
# (<name>.postgres.database.azure.com) and the cache
# (<name>.redis.cache.windows.net). A name derived from deployment_name can
# therefore collide with a vault or account SOMEBODY ELSE owns — and Azure
# refuses the create, after the plan looked fine. Each has an optional override
# that defaults to the derived name; the rule validated here is the SAME rule
# the provider module validates, so a bad override is refused at the stack
# boundary rather than one module deeper. Resource-group-scoped names (the AKS
# cluster) need no override for this reason and already have one for another.
# ---------------------------------------------------------------------------

variable "key_vault_name" {
  description = "Key Vault name. Empty derives \"<deployment_name>-kv\". Globally unique across Azure (3-24 letters, digits and single hyphens, starting with a letter, ending alphanumeric). The vault's dedicated resource group is \"<key_vault_name>-rg\"."
  type        = string
  default     = ""

  validation {
    condition     = var.key_vault_name == "" || (can(regex("^[a-zA-Z](?:[a-zA-Z0-9-]{1,22})[a-zA-Z0-9]$", var.key_vault_name)) && !can(regex("--", var.key_vault_name)))
    error_message = "key_vault_name must be empty (derive it) or 3-24 letters, digits or hyphens, start with a letter, end alphanumeric, and contain no consecutive hyphens."
  }
}

variable "storage_account_name" {
  description = "Storage account name the platform's blob adapter targets. Empty derives \"<deployment_name without hyphens>blob\". Globally unique across Azure (3-24 lowercase letters or digits)."
  type        = string
  default     = ""

  validation {
    condition     = var.storage_account_name == "" || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be empty (derive it) or 3-24 lowercase letters or digits (an Azure storage account name)."
  }
}

variable "postgres_server_name" {
  description = "PostgreSQL Flexible Server name (created server only). Empty derives \"<deployment_name>-pg\". Globally unique across Azure as <name>.postgres.database.azure.com (3-63 lowercase letters, digits and hyphens, starting with a letter, ending alphanumeric). The private DNS zone and the derived host follow it."
  type        = string
  default     = ""

  validation {
    condition     = var.postgres_server_name == "" || can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.postgres_server_name))
    error_message = "postgres_server_name must be empty (derive it) or 3-63 chars of lowercase letters, digits and hyphens, starting with a letter and ending alphanumeric."
  }
}

variable "redis_cache_name" {
  description = "Azure Cache for Redis name (enable_cache only). Empty derives \"<deployment_name>-redis\". Globally unique across Azure as <name>.redis.cache.windows.net (1-63 letters, digits and hyphens, starting and ending alphanumeric)."
  type        = string
  default     = ""

  validation {
    condition     = var.redis_cache_name == "" || can(regex("^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$", var.redis_cache_name))
    error_message = "redis_cache_name must be empty (derive it) or 1-63 letters, digits or hyphens, starting and ending alphanumeric."
  }
}

# ---------------------------------------------------------------------------
# Enable / disable toggles
# ---------------------------------------------------------------------------
# Each area of the substrate can be independently enabled or disabled. This lets
# one deployment manage ONLY its in-cluster and identity resources (namespaces,
# RWX storage, identity realm, extension claims) while a SEPARATE "cloud
# substrate" Terraform owns the shared cloud infra. When a cloud module is disabled, the
# stack CONSUMES the existing resource instead of creating it.

variable "enable_cluster" {
  description = "Create the AKS cluster (in var.network). Set false to consume an existing cluster, read by var.cluster_name / var.cluster_resource_group_name."
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
  description = "Create the Key Vault, the External Secrets reader identity, and the External Secrets Operator with its ClusterSecretStore (cluster-addons/external-secrets) — independent of enable_gateway_tls."
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

variable "enable_gateway_tls" {
  description = "Install the Gateway API edge (NGINX Gateway Fabric + Gateway, or a customer-managed Gateway) and cert-manager + ClusterIssuer on the (created or existing) cluster."
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

variable "resource_group_name" {
  description = "An EXISTING resource group every Azure resource this stack creates is placed in — the cluster, PostgreSQL, storage, key vault, cache and DNS zone alike. Empty (default) keeps each area in its own resource group (\"<name>-rg\", created by its module) and the cluster in the network's. A landing zone that grants a deployment exactly one resource group sets it."
  type        = string
  default     = ""
}

variable "cluster_resource_group_name" {
  description = "Resource group of the cluster. Empty uses var.resource_group_name, else var.network's resource group (the foundation's), else \"<deployment_name>-rg\"; it must already exist."
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

variable "cluster_outbound_type" {
  description = "AKS egress for the created cluster: \"loadBalancer\" (default — AKS's own public egress), \"userDefinedRouting\" (the node subnet's existing route decides, e.g. 0.0.0.0/0 to the network owner's firewall; needs network.route_table_id), \"managedNATGateway\" or \"userAssignedNATGateway\"."
  type        = string
  default     = "loadBalancer"
}

variable "cluster_private" {
  description = <<-EOT
    Kubernetes API reachability for the created cluster. null (default) keeps a
    public API endpoint (narrowed by cluster_authorized_ip_ranges). Set, the API
    is only on a private address inside the network:
      - public_fqdn : also publish that private address under a public DNS name,
                      for resolvers that cannot see Azure private DNS zones (a
                      network on custom DNS). The endpoint stays private.
    A private API is reached from inside the network — the management runner.
  EOT
  type = object({
    public_fqdn = optional(bool, false)
  })
  default = null
}

variable "cluster_entra_rbac" {
  description = <<-EOT
    Microsoft Entra ID authentication with Azure RBAC for the created cluster.
    null (default) keeps AKS certificate (local) accounts. With
    local_account_disabled = true the kubernetes/helm providers of this stack
    authenticate through kubelogin with the Azure CLI identity of whoever runs it
    (`az login`, or azure/login in CI) — which then needs an AKS RBAC role.
      - tenant_id              : "" uses the subscription's tenant
      - admin_group_object_ids : Entra groups granted cluster-admin
      - local_account_disabled : default true
  EOT
  type = object({
    tenant_id              = optional(string, "")
    admin_group_object_ids = optional(list(string), [])
    local_account_disabled = optional(bool, true)
  })
  default = null
}

variable "cluster_address_ranges" {
  description = "Kubernetes-internal address ranges of the created cluster (Azure CNI overlay). They must overlap neither the VNet nor ANY network it is peered or routed to — on an enterprise landing zone, ask for ranges unused in the corporate address plan. null keeps the cluster module's defaults."
  type = object({
    service_cidr   = string
    dns_service_ip = string
    pod_cidr       = string
  })
  default = null
}

variable "cluster_enable_log_analytics" {
  description = "Wire the created cluster's monitoring add-on to a Log Analytics workspace."
  type        = bool
  default     = false
}

variable "network" {
  description = <<-EOT
    The network this deployment lives in, CONSUMED from the foundation stack
    (stacks/azure/xema-foundation) — never created here, because it must exist
    before this stack runs: the management runner inside it is where this
    stack's data-plane resources (PostgreSQL roles, Key Vault secrets) are
    applied from. Pass the foundation's `network` output through unchanged.
    Required whenever this stack creates the cluster, a private PostgreSQL
    server, or any private backing service; null otherwise.
  EOT
  type = object({
    resource_group_name        = string
    vnet_id                    = string
    aks_subnet_id              = string
    postgres_subnet_id         = string
    private_endpoint_subnet_id = string
    private_dns_zone_ids       = map(string)
    # The route table on aks_subnet_id — needed with cluster_outbound_type =
    # "userDefinedRouting". Consumed, never managed.
    route_table_id = optional(string, "")
  })
  default = null
}

variable "backing_services_network_access" {
  description = "How the created cache, storage account and key vault are reached: \"private\" (public endpoint OFF, one private endpoint each in var.network) or \"public\" (public endpoint, TLS + key). The same closed set as postgres_network_access, and the same default."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public"], var.backing_services_network_access)
    error_message = "backing_services_network_access must be one of private, public."
  }
}

# ---------------------------------------------------------------------------
# Managed Postgres (modules/providers/azure/managed-postgres) — created only
# when enable_managed_postgres. Databases and roles are DERIVED (locals.tf),
# and ensured on an EXISTING server too (module.postgres_tenancy) when consumed.
# ---------------------------------------------------------------------------

variable "postgres_engine_version" {
  description = "Major Postgres version (created server only)."
  type        = string
  default     = "16"
}

variable "postgres_network_access" {
  description = "How the created server is reached: \"private\" (VNet-injected through network.postgres_subnet_id, which must be delegated to PostgreSQL), \"private_endpoint\" (no public access; a private endpoint in network.private_endpoint_subnet_id — no subnet delegation needed) or \"public\" (public endpoint restricted to postgres_public_firewall_rules)."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "private_endpoint", "public"], var.postgres_network_access)
    error_message = "postgres_network_access must be one of private, private_endpoint, public."
  }
}

variable "postgres_extensions" {
  description = "PostgreSQL extensions to allow-list on the CREATED server (its azure.extensions parameter), lowercase identifiers such as \"pg_trgm\". Empty (default) leaves Azure's default allow-list untouched. Not the `extensions` input, which is the platform's extension claims; ignored when enable_managed_postgres = false (a consumed server's parameters are its owner's)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.postgres_extensions : can(regex("^[a-z][a-z0-9_]*$", e))])
    error_message = "postgres_extensions entries must be lowercase identifiers matching ^[a-z][a-z0-9_]*$."
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

variable "platform_databases" {
  description = <<-EOT
    The logical databases to ensure on the CREATED server, by UNPREFIXED name
    (e.g. "identity", "billing", "temporal"). REQUIRED, no default: which
    databases exist is a fact about what the consumer deploys, derived from its
    own distribution — the substrate does not know it. Every name gets the ONE
    Postgres rewrite this stack applies (locals.tf): it is prefixed with the
    deployment name in identifier form, "<deployment_name with - as _>_<name>".
    Each name: lowercase letters, digits and underscores, starting with a
    letter. With enable_managed_postgres = false the SAME names (and the
    derived roles) are ensured on the EXISTING server through
    modules/postgres-tenancy — one stack instance per environment, each owning
    only its own prefixed set; pass [] there when the tenancy is managed
    elsewhere.
  EOT
  type        = set(string)

  validation {
    condition     = alltrue([for d in var.platform_databases : can(regex("^[a-z][a-z0-9_]{0,42}$", d))])
    error_message = "Each platform_databases entry must be 1-43 chars of lowercase letters, digits and underscores, starting with a letter (unprefixed; the stack prefixes the deployment name)."
  }
}

variable "existing_postgres_server_id" {
  description = "Resource id of an existing Flexible Server to host extension-claimed databases when enable_managed_postgres = false."
  type        = string
  default     = ""
}

variable "existing_postgres_host" {
  description = "FQDN of that existing server, for the postgresql provider when enable_managed_postgres = false (platform_databases tenancy, extension owner roles). Terraform connects to it DIRECTLY over SQL, so it must resolve and be reachable from where Terraform runs — for a private server, an in-VNet runner whose VNet is linked to the server's privatelink zone (README § Consume mode)."
  type        = string
  default     = ""
}

variable "existing_postgres_admin_login" {
  description = "Administrator login of the existing server (consume mode)."
  type        = string
  default     = ""
}

variable "existing_postgres_admin_password_key_vault_id" {
  description = <<-EOT
    Resource id of the Key Vault holding the EXISTING server's administrator
    password (consume mode), read by an azurerm_key_vault_secret data source
    under postgres_admin_password_secret_name. The stack instance that CREATED
    the server writes it there (enable_managed_postgres = true with
    enable_secrets_backend = true), so for a server this stack created
    elsewhere this is THAT instance's vault:
    `az keyvault show -n <its key_vault_name> --query id -o tsv`.

    There is deliberately no password input: a password typed into a tfvars
    file or an environment variable has been written somewhere before it
    reaches state, and a remote_state read would couple this root to another
    root's state backend. Read only when this instance runs SQL against the
    existing server — a non-empty platform_databases or an extension
    managed_databases claim — and required then; otherwise nothing is read.
    The principal running Terraform needs "Key Vault Secrets User" on it.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.existing_postgres_admin_password_key_vault_id == "" || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", var.existing_postgres_admin_password_key_vault_id))
    error_message = "existing_postgres_admin_password_key_vault_id must be a Key Vault resource id: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<name>."
  }
}

variable "postgres_admin_password_secret_name" {
  description = <<-EOT
    The Key Vault secret name that carries the PostgreSQL server administrator
    password — one name for both directions. With enable_managed_postgres =
    true AND enable_secrets_backend = true this stack WRITES the admin password
    of the server it creates into its own vault under this name; with
    enable_managed_postgres = false it READS the existing server's admin
    password from existing_postgres_admin_password_key_vault_id under it. Left
    at the default on both sides, the two match without coordination. Must not
    also be a key of key_vault_secrets.
  EOT
  type        = string
  default     = "postgres-admin-password"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,127}$", var.postgres_admin_password_secret_name))
    error_message = "postgres_admin_password_secret_name must be 1-127 letters, digits or hyphens (a Key Vault secret name)."
  }
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
# Gateway + TLS (modules/cluster-addons/gateway-tls); the secret store is cluster-addons/external-secrets
# ---------------------------------------------------------------------------

variable "acme_email" {
  description = "ACME account contact e-mail. Required when enable_gateway_tls."
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

variable "gateway_implementation" {
  description = "\"nginx-gateway-fabric\" (the stack installs the Gateway API CRDs, NGINX Gateway Fabric and the Gateway) or \"customer-managed\" (the customer provides the Gateway; set customer_gateway)."
  type        = string
  default     = "nginx-gateway-fabric"

  validation {
    condition     = contains(["nginx-gateway-fabric", "customer-managed"], var.gateway_implementation)
    error_message = "gateway_implementation must be one of nginx-gateway-fabric, customer-managed."
  }
}

variable "customer_gateway" {
  description = "The customer's existing Gateway ({ name, namespace, http_section_name, https_section_name }) when gateway_implementation = \"customer-managed\"; null otherwise."
  type = object({
    name               = string
    namespace          = string
    http_section_name  = string
    https_section_name = string
  })
  default = null
}

variable "gateway_hostname" {
  description = "Hostname of the Gateway listeners, which cert-manager issues the certificate for (a wildcard needs tls_solver = \"dns01-azure\"). Required with nginx-gateway-fabric."
  type        = string
  default     = ""
}

variable "max_request_body_mib" {
  description = "Request-body ceiling in MiB for every route on the Gateway (a finite default; configuration tightens it)."
  type        = number
  default     = 256
}

variable "gateway_infrastructure_annotations" {
  description = "Annotations on the Gateway's data-plane LoadBalancer Service (e.g. \"service.beta.kubernetes.io/azure-dns-label-name\")."
  type        = map(string)
  default     = {}
}

variable "gateway_load_balancer_ip" {
  description = "Pin the Gateway's LoadBalancer to a pre-allocated static IP. Empty lets Azure assign one."
  type        = string
  default     = ""
}

# The two in-cluster resource NAMES a consumer's manifests reference — the
# cert-manager.io/cluster-issuer annotation and every ExternalSecret's
# secretStoreRef. Exposed as stack outputs (and in the substrate map) so a
# consumer reads them from the stack instead of restating today's defaults.

variable "cluster_issuer_name" {
  description = "Name of the ACME ClusterIssuer the addon creates (what the Gateway references in cert-manager.io/cluster-issuer). A DNS-1123 subdomain name."
  type        = string
  default     = "letsencrypt"

  validation {
    condition     = length(var.cluster_issuer_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.cluster_issuer_name))
    error_message = "cluster_issuer_name must be a DNS-1123 subdomain name: lowercase letters, digits, hyphens and dots, starting and ending alphanumeric, at most 253 chars."
  }
}

variable "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore the addon creates (what ExternalSecret resources reference in secretStoreRef). A DNS-1123 subdomain name. Only created when enable_secrets_backend."
  type        = string
  default     = "platform"

  validation {
    condition     = length(var.cluster_secret_store_name) <= 253 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.cluster_secret_store_name))
    error_message = "cluster_secret_store_name must be a DNS-1123 subdomain name: lowercase letters, digits, hyphens and dots, starting and ending alphanumeric, at most 253 chars."
  }
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
# Workload namespaces (modules/cluster-addons/workload-namespaces)
# ---------------------------------------------------------------------------

variable "workload_namespaces" {
  description = <<-EOT
    The roster of namespaces to ensure exist on the (created or consumed)
    cluster, by full name. REQUIRED, no default: which namespaces a deployment
    runs in is a fact the consumer derives from what it deploys — the substrate
    does not know it. Nothing here is derived from deployment_name; pass the
    names you want (a consumer that spells them "<deployment_name>-<role>" does
    that derivation itself). Each name is a DNS-1123 label. Ignored when
    enable_workload_namespaces = false.
  EOT
  type        = set(string)

  validation {
    condition     = alltrue([for ns in var.workload_namespaces : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", ns))])
    error_message = "Each workload_namespaces entry must be a DNS-1123 label (1-63 lowercase alphanumerics or hyphens, starting and ending alphanumeric)."
  }
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
  description = "Human-readable realm display name shown on login screens. Empty uses deployment_name verbatim; the consumer names its product, the substrate does not."
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
# Extension substrate claims (see docs/extensions.md, extensions.tf)
# ---------------------------------------------------------------------------

variable "extensions" {
  description = <<-EOT
    Dedicated substrate claimed by extensions — consumers of this substrate that
    need a cloud resource of their own — keyed by a stable extension id the
    consumer chooses. Each value carries any subset of a CLOSED set of three
    claim kinds:
      - object_buckets   : map(stable id => { name, acl?, versioning? })  (name = a storage account name)
      - managed_databases: map(stable id => { database, owner? })  (on the resolved server)
      - dns_records      : map(stable id => { name, type?, value, ttl? })  (requires enable_dns)
    Declare an extension here only when it needs a DEDICATED out-of-cluster
    resource that nothing running in the cluster can create. What the consumer
    provisions for itself at runtime (schemas on a shared database, in-cluster
    objects) needs NO entry.
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

# ---------------------------------------------------------------------------
# Deployer identity — the namespaces a deployment owns and the least-privileged
# ServiceAccount its pipeline deploys as. Default OFF: a consumer adopting a new
# module version must not silently gain a ServiceAccount and a token it did not
# ask for. Turning it on is one flag plus the namespace the deployment declares.
# ---------------------------------------------------------------------------

variable "enable_deployer_identity" {
  description = "Manage the deployment's namespaces, its least-privileged deployer ServiceAccount, that account's token, and the cluster-identity facts a pipeline verifies before it writes."
  type        = bool
  default     = false
}

variable "deployer_namespace" {
  description = <<-EOT
    The namespace the deployment's workloads run in — the one its own descriptor
    DECLARES. Required when enable_deployer_identity = true, and deliberately not
    derived from deployment_name or from any directory: a namespace inferred from
    a folder is how a deployment declaring `xema-prod` came to be asked for a
    namespace named after the directory holding its files.
  EOT
  type        = string
  default     = ""
}

variable "deployer_additional_namespaces" {
  description = "Every OTHER namespace the same identity deploys into — typically the deployment's infrastructure namespace. No implicit suffix is derived."
  type        = list(string)
  default     = []
}

variable "deployer_service_account_name" {
  description = "Name of the deployer ServiceAccount, its Role and its RoleBindings. The token Secret is \"<name>-token\"."
  type        = string
  default     = "github-deployer"
}

variable "deployer_manage_namespaces" {
  description = "Create the deployer's namespaces here. False when they already exist and are owned elsewhere; the grants are still created inside them."
  type        = bool
  default     = true
}

variable "deployer_context_name" {
  description = "The alias written into the emitted kubeconfig's context/cluster/user. An alias identifies no cluster — the identity is the `cluster_identity` output — but a consumer that still compares one needs it to match."
  type        = string
  default     = "default"
}
