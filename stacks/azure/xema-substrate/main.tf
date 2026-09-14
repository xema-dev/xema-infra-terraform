# The Azure Xema substrate stack. Each area is independently toggleable (see
# variables.tf § enable_*) so a deployment can manage ONLY its xema-specific
# resources and CONSUME cloud infra owned by a separate Terraform. Every name is
# DERIVED from var.deployment_name (locals.tf); nothing here names a deployment.

# ---------------------------------------------------------------------------
# Cross-input guards. Terraform 1.6 validation blocks see one variable only, so
# the requirements that span inputs fail fast here, naming the input.
# ---------------------------------------------------------------------------

resource "terraform_data" "input_guards" {
  lifecycle {
    precondition {
      condition     = !var.enable_dns || var.apex_domain != ""
      error_message = "enable_dns = true requires apex_domain."
    }
    precondition {
      condition     = !var.enable_ingress_tls || var.acme_email != ""
      error_message = "enable_ingress_tls = true requires acme_email (the ACME account contact)."
    }
    precondition {
      condition     = !(var.enable_ingress_tls && local.dns01) || var.enable_dns
      error_message = "tls_solver = \"dns01-azure\" requires enable_dns = true (the solver edits this stack's zone through workload identity)."
    }
    precondition {
      condition     = !var.enable_identity_realm || var.keycloak_url != ""
      error_message = "enable_identity_realm = true requires keycloak_url."
    }
    precondition {
      condition     = var.enable_cluster || !local.needs_cluster_facts || local.cluster_name != ""
      error_message = "Consuming an existing cluster requires cluster_name (and cluster_resource_group_name)."
    }
  }
}

# ---------------------------------------------------------------------------
# Cloud infra (optional — usually owned by a separate "cloud substrate" tf)
# ---------------------------------------------------------------------------

module "cluster" {
  source = "../../../modules/providers/azure/cluster"
  count  = var.enable_cluster ? 1 : 0

  name                 = local.cluster_name
  region               = var.region
  kubernetes_version   = var.kubernetes_version
  node_pools           = var.node_pools
  default_pool_id      = var.default_pool_id
  resource_group_name  = var.cluster_resource_group_name # "" => the module creates "<name>-rg"
  sku_tier             = var.azure_sizing.aks_sku_tier
  authorized_ip_ranges = var.cluster_authorized_ip_ranges
  enable_log_analytics = var.cluster_enable_log_analytics
  tags                 = local.tags
}

# When NOT creating the cluster, read the existing one by name so the
# kubernetes/helm providers can target it and workload identity can federate
# against its OIDC issuer.
data "azurerm_kubernetes_cluster" "existing" {
  count = (!var.enable_cluster && local.needs_cluster_facts) ? 1 : 0

  name                = local.cluster_name
  resource_group_name = local.cluster_resource_group_name
}

# Minted HERE so the postgresql provider can be configured without reading a
# module output (see locals.tf). Kept in state, exposed as a sensitive output.
resource "random_password" "postgres_admin" {
  count = var.enable_managed_postgres && var.postgres_administrator_password == "" ? 1 : 0

  length  = 32
  special = false
}

module "postgres" {
  source = "../../../modules/providers/azure/managed-postgres"
  count  = var.enable_managed_postgres ? 1 : 0

  name           = local.postgres_name
  region         = var.region
  engine_version = var.postgres_engine_version
  size           = var.azure_sizing.postgres_sku_name
  storage_mb     = var.azure_sizing.postgres_storage_mb
  node_count     = var.azure_sizing.postgres_ha ? 2 : 1

  network_access        = var.postgres_network_access
  vpc_id                = local.vpc_id
  delegated_subnet_id   = local.delegated_subnet_id
  public_firewall_rules = var.postgres_public_firewall_rules

  private_dns_zone_name  = local.postgres_private_dns_zone_name
  administrator_login    = local.pg_admin_login
  administrator_password = local.pg_admin_password
  backup_retention_days  = local.postgres_backup_retention

  databases    = local.postgres_databases
  roles        = local.postgres_roles
  role_options = local.postgres_role_options
  tags         = local.tags
}

module "dns" {
  source = "../../../modules/providers/azure/dns"
  count  = var.enable_dns ? 1 : 0

  domain = var.apex_domain
  region = var.region

  # Base records MERGED with the extension-claimed records (extensions.tf).
  records = merge(var.dns_records, local.ext_dns_records)

  # The cert-manager DNS-01 identity, only when that solver is in use.
  dns01_workload_identity = {
    enabled         = var.enable_ingress_tls && local.dns01
    oidc_issuer_url = coalesce(local.oidc_issuer_url, "")
  }

  tags = local.tags
}

module "blob" {
  source = "../../../modules/providers/azure/object-bucket"
  count  = var.enable_object_storage ? 1 : 0

  name        = local.blob_account_name
  region      = var.region
  acl         = "private"
  versioning  = var.blob_versioning
  replication = var.azure_sizing.blob_replication
  containers  = local.blob_containers
  tags        = local.tags
}

module "secrets_backend" {
  source = "../../../modules/providers/azure/secrets-backend"
  count  = var.enable_secrets_backend ? 1 : 0

  name   = local.key_vault_name
  region = var.region

  secret_names  = keys(var.key_vault_secrets)
  secret_values = sensitive(var.key_vault_secrets)

  workload_identity = {
    enabled         = true
    oidc_issuer_url = coalesce(local.oidc_issuer_url, "")
  }

  purge_protection_enabled = local.key_vault_purge_protection
  tags                     = local.tags
}

module "cache" {
  source = "../../../modules/providers/azure/cache"
  count  = var.enable_cache ? 1 : 0

  name     = local.redis_name
  region   = var.region
  sku      = var.azure_sizing.redis_sku
  capacity = var.azure_sizing.redis_capacity
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Xema-specific in-cluster + identity resources
# ---------------------------------------------------------------------------

# Azure Files CSI is built into AKS, so the provisioner chart is NOT managed —
# only the StorageClass, pointed at file.csi.azure.com with NFS parameters.
module "rwx_storage" {
  source = "../../../modules/cluster-addons/rwx-storage"
  count  = var.enable_rwx_storage ? 1 : 0

  manage_provisioner_chart  = false
  storage_class_name        = var.rwx_storage_class_name
  storage_class_provisioner = "file.csi.azure.com"
  storage_class_parameters  = var.rwx_storage_class_parameters
  is_default_class          = var.rwx_is_default_class
  allow_volume_expansion    = var.rwx_allow_volume_expansion
}

module "workload_namespaces" {
  source = "../../../modules/cluster-addons/workload-namespaces"
  count  = var.enable_workload_namespaces ? 1 : 0

  namespaces = local.workload_namespaces
  labels     = var.workload_namespace_labels
}

module "ingress_tls" {
  source = "../../../modules/cluster-addons/ingress-tls"
  count  = var.enable_ingress_tls ? 1 : 0

  acme_email                  = var.acme_email
  acme_server                 = var.acme_server
  tls_solver                  = var.tls_solver
  ingress_service_annotations = var.ingress_service_annotations
  ingress_load_balancer_ip    = var.ingress_load_balancer_ip

  dns01_azure = local.dns01 && var.enable_dns ? {
    subscription_id     = module.dns[0].subscription_id
    resource_group_name = module.dns[0].resource_group_name
    hosted_zone_name    = module.dns[0].domain
    client_id           = module.dns[0].dns01_client_id
  } : null

  external_secrets_enabled = var.enable_secrets_backend
  azure_key_vault_store = var.enable_secrets_backend ? {
    vault_uri = module.secrets_backend[0].vault_uri
    client_id = module.secrets_backend[0].client_id
    tenant_id = module.secrets_backend[0].tenant_id
  } : null
}

module "identity_realm" {
  source = "../../../modules/identity-realm"
  count  = var.enable_identity_realm ? 1 : 0

  realm_name            = local.realm_name
  display_name          = local.realm_display_name
  access_token_lifespan = var.realm_access_token_lifespan
  clients               = var.realm_clients
  realm_roles           = var.realm_roles
  protocol_mappers      = var.realm_protocol_mappers
}
