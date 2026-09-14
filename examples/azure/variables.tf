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
  description = "Ensure the derived workload namespaces exist."
  type        = bool
  default     = true
}

variable "enable_ingress_tls" {
  description = "Install ingress-nginx + cert-manager + External Secrets."
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

variable "existing_vnet_id" {
  description = "VNet id for a created private Postgres when the cluster is consumed."
  type        = string
  default     = ""
}

variable "existing_delegated_subnet_id" {
  description = "Delegated subnet id for a created private Postgres when the cluster is consumed."
  type        = string
  default     = ""
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

variable "existing_postgres_admin_password" {
  description = "Existing server admin password (consume mode)."
  type        = string
  default     = ""
  sensitive   = true
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

variable "enable_billing_database" {
  description = "Also derive the billing_api database."
  type        = bool
  default     = false
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

# --- ingress + tls ---

variable "acme_email" {
  description = "ACME account contact (required when enable_ingress_tls)."
  type        = string
  default     = ""
}

variable "acme_server" {
  description = "ACME directory URL."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "tls_solver" {
  description = "\"http01\" or \"dns01-azure\"."
  type        = string
  default     = "http01"
}

variable "ingress_service_annotations" {
  description = "Annotations on the ingress LoadBalancer Service."
  type        = map(string)
  default     = {}
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
  description = "Dedicated out-of-cluster substrate claimed by biomes, keyed by extension id. See docs/extensions.md."
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
