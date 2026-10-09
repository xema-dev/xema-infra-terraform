# Pass-through variables for the Azure substrate example root. Each maps
# directly onto a stack input; see ../../stacks/azure/xema-substrate for the
# full descriptions.
#
# Defaults mirror the stack's defaults so this root works in BOTH modes:
#   - greenfield (terraform.tfvars.example): create everything.
#   - consume    (consume.tfvars.example):   disable cloud infra, consume an existing
#                                            cluster by name + an existing server.

# --- identity ---

variable "deployment_name" {
  description = "The one name everything derives from (3-20 lowercase chars, single hyphens)."
  type        = string
}

variable "environment" {
  description = "One of dev, prod."
  type        = string
}

variable "region" {
  description = "Azure location."
  type        = string
}

variable "apex_domain" {
  description = "Public DNS zone apex (required when enable_dns)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags merged over the derived set."
  type        = map(string)
  default     = {}
}

# --- overrides for the GLOBALLY-unique derived names (validated by the stack) ---

variable "operator_vault_name" {
  description = "Operator vault name (break-glass/infra secrets, never projected into the cluster). Empty derives \"<deployment_name>-kv\"; set it when the derived name collides with a vault another tenant owns."
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Blob storage account name. Empty derives \"<deployment_name without hyphens>blob\"."
  type        = string
  default     = ""
}

variable "postgres_server_name" {
  description = "Flexible Server name (created server only). Empty derives \"<deployment_name>-pg\"."
  type        = string
  default     = ""
}

variable "redis_cache_name" {
  description = "Azure Cache for Redis name (enable_cache only). Empty derives \"<deployment_name>-redis\"."
  type        = string
  default     = ""
}

# --- enable / disable toggles (defaults = greenfield) ---

variable "enable_cluster" {
  description = "Create AKS + VNet. false ⇒ consume an existing cluster (read by cluster_name)."
  type        = bool
  default     = true
}

variable "enable_managed_postgres" {
  description = "Create the Flexible Server. false ⇒ extension DBs target existing_postgres_server_id."
  type        = bool
  default     = true
}

variable "enable_dns" {
  description = "Manage the apex_domain zone. false ⇒ DNS owned elsewhere."
  type        = bool
  default     = true
}

variable "enable_object_storage" {
  description = "Create the blob storage account."
  type        = bool
  default     = true
}

variable "enable_secrets_backend" {
  description = "Create the Key Vault + External Secrets reader identity."
  type        = bool
  default     = true
}

variable "enable_cache" {
  description = "Create a managed Azure Cache for Redis (off: valkey runs in-cluster)."
  type        = bool
  default     = false
}

variable "enable_rwx_storage" {
  description = "Create the RWX StorageClass (Azure Files CSI, NFS)."
  type        = bool
  default     = true
}

variable "enable_workload_namespaces" {
  description = "Ensure the workload_namespaces roster exists."
  type        = bool
  default     = true
}

variable "enable_gateway_tls" {
  description = "Install the Gateway API edge (NGINX Gateway Fabric + Gateway) + cert-manager."
  type        = bool
  default     = true
}

variable "enable_identity_realm" {
  description = "Manage the Keycloak realm (needs a reachable keycloak_url)."
  type        = bool
  default     = true
}

# --- consume-mode facts ---

variable "cluster_name" {
  description = "Existing (or override) AKS cluster name. Empty derives \"<deployment_name>-aks\"."
  type        = string
  default     = ""
}

variable "cluster_resource_group_name" {
  description = "Resource group of the cluster. Empty derives \"<deployment_name>-rg\"."
  type        = string
  default     = ""
}

variable "network" {
  description = "The foundation stack's `network` output (stacks/azure/xema-foundation), passed through unchanged. Required when this root creates the cluster, a private PostgreSQL server or a private backing service."
  type = object({
    resource_group_name        = string
    vnet_id                    = string
    aks_subnet_id              = string
    postgres_subnet_id         = string
    private_endpoint_subnet_id = string
    private_dns_zone_ids       = map(string)
  })
  default = null
}

variable "backing_services_network_access" {
  description = "private (default: cache, storage account and key vault behind private endpoints) or public."
  type        = string
  default     = "private"
}

variable "existing_postgres_server_id" {
  description = "Existing Flexible Server id hosting extension databases (consume mode)."
  type        = string
  default     = ""
}

variable "existing_postgres_host" {
  description = "Existing Flexible Server FQDN (consume mode)."
  type        = string
  default     = ""
}

variable "existing_postgres_admin_login" {
  description = "Existing server admin login (consume mode)."
  type        = string
  default     = ""
}

variable "existing_postgres_admin_password_key_vault_id" {
  description = "Resource id of the Key Vault holding the existing server's admin password (consume mode) — the vault of the instance that created the server. Read, never typed."
  type        = string
  default     = ""
}

variable "postgres_admin_password_secret_name" {
  description = "Key Vault secret name carrying the server admin password: written by the creating instance, read by a consuming one."
  type        = string
  default     = "postgres-admin-password"
}

# --- provider credentials ---

variable "azure_subscription_id" {
  description = "Azure subscription id. Empty defers to ARM_SUBSCRIPTION_ID."
  type        = string
  default     = ""
}

variable "keycloak_url" {
  description = "Base URL of the Keycloak server. Required only when enable_identity_realm."
  type        = string
  default     = ""
}

variable "keycloak_client_id" {
  description = "Keycloak admin client id for the client-credentials grant."
  type        = string
  default     = ""
}

variable "keycloak_client_secret" {
  description = "Keycloak admin client secret for the client-credentials grant."
  type        = string
  default     = ""
  sensitive   = true
}

variable "keycloak_admin_realm" {
  description = "Realm the admin client authenticates against."
  type        = string
  default     = "master"
}

# --- sizing + cluster ---

variable "azure_sizing" {
  description = "Azure SKU choices (see the stack)."
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
}

variable "kubernetes_version" {
  description = "AKS control-plane version prefix (e.g. \"1.31\")."
  type        = string
  default     = "1.31"
}

variable "node_pools" {
  description = "Node pools keyed by a stable pool id (also the AKS agent pool name)."
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
  description = "Which key in node_pools is the AKS default (system) pool."
  type        = string
  default     = "generic"
}

# --- postgres ---

variable "postgres_network_access" {
  description = "\"private\" (VNet-injected) or \"public\" (firewall rules)."
  type        = string
  default     = "private"
}

variable "postgres_public_firewall_rules" {
  description = "Firewall rules for a PUBLIC server, keyed by a stable id."
  type = map(object({
    start_ip_address = string
    end_ip_address   = string
  }))
  default = {}
}

variable "platform_databases" {
  description = "Logical databases to ensure on the created server, UNPREFIXED; the stack prefixes \"<deployment_name>_\" (hyphens as underscores). Required — derive it from what you deploy."
  type        = set(string)
}

# --- workload namespaces ---

variable "workload_namespaces" {
  description = "Namespaces to ensure exist, by full name. Required — derive it from what you deploy."
  type        = set(string)
}

# --- dns ---

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

# --- secrets backend ---

variable "key_vault_secrets" {
  description = "Secrets to seed into the Key Vault, keyed by name. Supply via TF_VAR_key_vault_secrets, never a committed file."
  type        = map(string)
  default     = {}
}

# --- gateway + tls ---

variable "acme_email" {
  description = "ACME account contact; required exactly when a listener is managed (or the Gateway is customer-managed)."
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME directory URL."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "tls_solver" {
  description = "\"http01\" or \"dns01-azure\"; required exactly when a listener is managed (or the Gateway is customer-managed)."
  type        = string
  default     = null
}

variable "gateway_infrastructure_annotations" {
  description = "Annotations on the Gateway's data-plane LoadBalancer Service."
  type        = map(string)
  default     = {}
}

variable "gateway_implementation" {
  description = "\"nginx-gateway-fabric\" (installed here) or \"customer-managed\" (set customer_gateway)."
  type        = string
  default     = "nginx-gateway-fabric"
}

variable "customer_gateway" {
  description = "The customer's existing Gateway when gateway_implementation = \"customer-managed\"."
  type = object({
    name                = string
    namespace           = string
    http_section_name   = string
    https_section_names = set(string)
  })
  default = null
}

variable "gateway_listeners" {
  description = "The Gateway's HTTPS listeners, keyed by listener name: { hostname, certificate_mode = managed | customer_supplied, secret_name (customer_supplied only) }. One hostname and one certificate each. Required with nginx-gateway-fabric."
  type = map(object({
    hostname         = string
    certificate_mode = string
    secret_name      = optional(string)
  }))
  default = {}
}

variable "max_request_body_mib" {
  description = "Request-body ceiling in MiB for every route on the Gateway."
  type        = number
  default     = 256
}

variable "gateway_load_balancer_ip" {
  description = "Pin the Gateway's LoadBalancer to a pre-allocated static IP."
  type        = string
  default     = ""
}

variable "cluster_issuer_name" {
  description = "ACME ClusterIssuer name (cert-manager.io/cluster-issuer). Read it back from the stack output rather than restating it in manifests."
  type        = string
  default     = "letsencrypt"
}

variable "secret_store_name" {
  description = "SecretStore name in each boundary namespace (ExternalSecret secretStoreRef.name, kind SecretStore). Read it back from the stack output rather than restating it in manifests."
  type        = string
  default     = "platform"
}

variable "secret_store_boundaries" {
  description = "Secret trust boundaries, keyed by boundary name. Each gets its own Key Vault, private endpoint, identity and namespaced SecretStores; vault_name is optional (empty derives \"<deployment_name>-<boundary>-kv\", refused when invalid). See the stack's secret_store_boundaries."
  type = map(object({
    namespaces = list(string)
    vault_name = optional(string, "")
  }))
  default = {}
}

# --- identity realm ---

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

# --- extensions ---

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
