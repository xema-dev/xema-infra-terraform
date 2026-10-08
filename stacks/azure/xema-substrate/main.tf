# The Azure substrate stack. Each area is independently toggleable (see
# variables.tf § enable_*) so a deployment can manage ONLY its in-cluster and
# identity resources and CONSUME cloud infra owned by a separate Terraform.
# Every name is DERIVED from var.deployment_name (locals.tf); nothing here
# names a deployment, a service or an application — the database and
# namespace rosters are inputs the consumer supplies.

# ---------------------------------------------------------------------------
# Cross-input guards. Terraform 1.6 validation blocks see one variable only, so
# the requirements that span inputs fail fast here, naming the input.
# ---------------------------------------------------------------------------

resource "terraform_data" "input_guards" {
  lifecycle {
    precondition {
      condition     = var.network != null || !(var.enable_cluster || (var.enable_managed_postgres && contains(["private", "private_endpoint"], var.postgres_network_access)) || length(local.private_endpoint_services_wanted) > 0)
      error_message = "network is required when this stack creates the cluster, a private PostgreSQL server, or a private backing service: pass the foundation stack's `network` output."
    }
    precondition {
      condition     = var.network == null || alltrue([for s in local.private_endpoint_services : contains(keys(var.network.private_dns_zone_ids), s)])
      error_message = "A private backing service needs its private DNS zone: the foundation's private_link_services must include every one of ${jsonencode(local.private_endpoint_services_wanted)}."
    }
    precondition {
      condition     = !var.enable_dns || var.apex_domain != ""
      error_message = "enable_dns = true requires apex_domain."
    }
    precondition {
      condition     = !var.enable_gateway_tls || var.acme_email != ""
      error_message = "enable_gateway_tls = true requires acme_email (the ACME account contact)."
    }
    precondition {
      condition     = !(var.enable_gateway_tls && local.dns01) || var.enable_dns
      error_message = "tls_solver = \"dns01-azure\" requires enable_dns = true (the solver edits this stack's zone through workload identity)."
    }
    precondition {
      condition     = !var.enable_identity_realm || var.keycloak_url != ""
      error_message = "enable_identity_realm = true requires keycloak_url."
    }
    precondition {
      condition     = !(var.enable_managed_postgres && var.enable_secrets_backend) || !contains(keys(var.key_vault_secrets), var.postgres_admin_password_secret_name)
      error_message = "key_vault_secrets has a key named \"${var.postgres_admin_password_secret_name}\", which is postgres_admin_password_secret_name — the secret this stack writes the created server's admin password to. Rename one of them."
    }
    precondition {
      condition     = !var.enable_deployer_identity || var.deployer_namespace != ""
      error_message = "enable_deployer_identity = true requires deployer_namespace: the namespace a deployment declares is a fact about the deployment, and the substrate refuses to invent one from deployment_name or from a directory."
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
  resource_group_name  = local.cluster_resource_group_name
  vnet_id              = local.vpc_id
  node_subnet_id       = var.network == null ? "" : var.network.aks_subnet_id
  sku_tier             = var.azure_sizing.aks_sku_tier
  authorized_ip_ranges = var.cluster_authorized_ip_ranges
  enable_log_analytics = var.cluster_enable_log_analytics
  tags                 = local.tags

  outbound_type                       = var.cluster_outbound_type
  route_table_id                      = var.network == null ? "" : var.network.route_table_id
  private_cluster_enabled             = var.cluster_private != null
  private_cluster_public_fqdn_enabled = var.cluster_private != null ? var.cluster_private.public_fqdn : false
  entra_rbac                          = var.cluster_entra_rbac
  network_policy_engine               = var.cluster_network_policy_engine

  # null = the cluster module's own defaults (its range variables are non-nullable).
  service_cidr   = var.cluster_address_ranges != null ? var.cluster_address_ranges.service_cidr : null
  dns_service_ip = var.cluster_address_ranges != null ? var.cluster_address_ranges.dns_service_ip : null
  pod_cidr       = var.cluster_address_ranges != null ? var.cluster_address_ranges.pod_cidr : null
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
  zone           = var.postgres_zone == null ? "" : var.postgres_zone

  network_access        = var.postgres_network_access
  vpc_id                = local.vpc_id
  delegated_subnet_id   = var.postgres_network_access == "private" ? local.delegated_subnet_id : ""
  resource_group_name   = var.resource_group_name
  public_firewall_rules = var.postgres_public_firewall_rules

  private_dns_zone_name           = local.postgres_private_dns_zone_name
  administrator_login             = local.pg_admin_login
  generate_administrator_password = false # minted by the stack (random_password.postgres_admin) or supplied
  administrator_password          = local.pg_admin_password
  backup_retention_days           = local.postgres_backup_retention
  extensions                      = var.postgres_extensions

  databases       = local.postgres_databases
  database_owners = local.postgres_database_owners
  roles           = local.postgres_roles
  role_options    = local.postgres_role_options
  tags            = local.tags
}

# CONSUME MODE: the server already exists — another environment's, another
# team's, a server shared between this deployment's dev and prod — so it has no
# control plane this stack owns, and the tenancy is done INSIDE it, over SQL,
# by modules/postgres-tenancy through the postgresql provider (providers.tf,
# which targets the existing server's admin credentials in this mode).
#
# The databases and roles are the SAME derivation the created server gets
# (locals.tf): `<deployment>_<name>` for every platform_databases entry, the
# `<deployment>` app role and its `_provisioner` sibling. So two instances of
# this stack — one per environment — pointed at ONE server each ensure exactly
# their own set, and neither can name the other's: every name carries its
# deployment. Until this existed a consumed server got NO databases and NO roles
# from here, so every environment after the first had no producer for them.
#
# The tenancy module creates-or-adopts what it is told and touches nothing
# else (no drop of unnamed databases), which is what makes a shared server safe
# to manage from N stacks. ABSENT IS THE IDENTITY: an empty platform_databases
# in consume mode instantiates nothing — a consumer that manages its tenancy
# elsewhere keeps exactly today's plan.
module "postgres_tenancy" {
  source = "../../../modules/postgres-tenancy"
  count  = !var.enable_managed_postgres && length(local.postgres_databases) > 0 ? 1 : 0

  # The provider's username (providers.tf). On PostgreSQL 16+ the module grants
  # it every managed role, without which the ownership and grants below cannot
  # be applied by a non-superuser admin (modules/postgres-tenancy/README.md).
  connecting_role = local.pg_admin_login

  databases    = local.postgres_databases
  roles        = toset(local.postgres_roles)
  role_options = local.postgres_role_options

  # The same ownership rule as the created server (locals.tf).
  database_owners = local.postgres_database_owners
  connect_grants  = local.postgres_connect_grants
}

# The existing server's admin password, read from the Key Vault the creating
# instance wrote it to (variables.tf § existing_postgres_admin_password_key_vault_id)
# — by reference, never typed, never another root's state. The preconditions
# run before the read, so a missing input is named instead of surfacing as an
# Azure 404 or a provider connection error.
data "azurerm_key_vault_secret" "existing_postgres_admin" {
  count = local.pg_consume_runs_sql ? 1 : 0

  name         = var.postgres_admin_password_secret_name
  key_vault_id = var.existing_postgres_admin_password_key_vault_id

  lifecycle {
    precondition {
      condition     = var.existing_postgres_host != "" && var.existing_postgres_admin_login != ""
      error_message = "enable_managed_postgres = false with something to ensure on the existing server (a non-empty platform_databases, or an extension managed_databases claim), so this stack connects to it over SQL — set existing_postgres_host and existing_postgres_admin_login, or pass platform_databases = [] if the tenancy is managed elsewhere."
    }
    precondition {
      condition     = var.existing_postgres_admin_password_key_vault_id != ""
      error_message = "enable_managed_postgres = false with something to ensure on the existing server, so its admin password is read from Key Vault — set existing_postgres_admin_password_key_vault_id to the vault the creating instance wrote it to (secret \"${var.postgres_admin_password_secret_name}\"), or pass platform_databases = [] if the tenancy is managed elsewhere."
    }
  }
}

module "dns" {
  source = "../../../modules/providers/azure/dns"
  count  = var.enable_dns ? 1 : 0

  domain = var.apex_domain
  region = var.region

  # Base records MERGED with the extension-claimed records (extensions.tf).
  records             = merge(var.dns_records, local.ext_dns_records)
  resource_group_name = var.resource_group_name

  # The cert-manager DNS-01 identity, only when that solver is in use.
  dns01_workload_identity = {
    enabled         = var.enable_gateway_tls && local.dns01
    oidc_issuer_url = local.oidc_issuer_url
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

  public_network_access_enabled = !local.private_backing_services
  resource_group_name           = var.resource_group_name
  tags                          = local.tags
}

module "secrets_backend" {
  source = "../../../modules/providers/azure/secrets-backend"
  count  = var.enable_secrets_backend ? 1 : 0

  name   = local.key_vault_name
  region = var.region

  # The seeded secrets, plus the created server's admin password under
  # postgres_admin_password_secret_name (locals.tf) — the one place a consume-
  # mode instance on the same server reads it from.
  secret_names  = setunion(keys(var.key_vault_secrets), local.pg_admin_password_secret_names)
  secret_values = sensitive(merge(var.key_vault_secrets, local.pg_admin_password_secret))

  workload_identity = {
    enabled         = true
    oidc_issuer_url = local.oidc_issuer_url
  }

  purge_protection_enabled      = local.key_vault_purge_protection
  public_network_access_enabled = !local.private_backing_services
  resource_group_name           = var.resource_group_name
  tags                          = local.tags
}

module "cache" {
  source = "../../../modules/providers/azure/cache"
  count  = var.enable_cache ? 1 : 0

  name     = local.redis_name
  region   = var.region
  sku      = var.azure_sizing.redis_sku
  capacity = var.azure_sizing.redis_capacity

  public_network_access_enabled = !local.private_backing_services
  resource_group_name           = var.resource_group_name
  tags                          = local.tags
}

# Optional container registry: Premium, private only, AcrPull for the cluster's
# kubelet identity. The identity that PUSHES images is the consumer's own CI
# principal, granted AcrPush by the consumer — never created here.
module "container_registry" {
  source = "../../../modules/providers/azure/container-registry"
  count  = var.enable_container_registry ? 1 : 0

  name                = local.registry_name
  region              = var.region
  resource_group_name = var.resource_group_name
  tags                = local.tags

  pull_principal_ids = { kubelet = local.kubelet_identity_object_id }
}

# ---------------------------------------------------------------------------
# Private endpoints — one per created backing service when
# backing_services_network_access = "private", and always one for the registry. Each service module only turns
# its public endpoint off; the network side is composed here, in the network
# the foundation owns.
# ---------------------------------------------------------------------------

locals {
  private_endpoint_targets = {
    blob     = one(module.blob[*].account_id)
    redis    = one(module.cache[*].id)
    vault    = one(module.secrets_backend[*].key_vault_id)
    postgres = one(module.postgres[*].cluster_id)
    acr      = one(module.container_registry[*].id)
  }
}

module "private_endpoint" {
  source   = "../../../modules/providers/azure/private-endpoint"
  for_each = toset(local.private_endpoint_services)

  name                = "${local.dep}-${each.value}"
  region              = var.region
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : var.network.resource_group_name
  service             = each.value
  target_resource_id  = local.private_endpoint_targets[each.value]
  subnet_id           = var.network.private_endpoint_subnet_id
  private_dns_zone_id = var.network.private_dns_zone_ids[each.value]
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# In-cluster + identity resources
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

  namespaces = var.workload_namespaces
  labels     = var.workload_namespace_labels
}

module "deployer_identity" {
  source = "../../../modules/cluster-addons/deployer-identity"
  count  = var.enable_deployer_identity ? 1 : 0

  deployment_name       = local.dep
  namespace             = var.deployer_namespace
  additional_namespaces = var.deployer_additional_namespaces
  service_account_name  = var.deployer_service_account_name
  manage_namespaces     = var.deployer_manage_namespaces
  context_name          = var.deployer_context_name

  cluster_endpoint           = local.kube_host != null ? local.kube_host : ""
  cluster_ca_certificate_b64 = local.kube_ca_b64 != null ? local.kube_ca_b64 : ""
}

module "gateway_tls" {
  source = "../../../modules/cluster-addons/gateway-tls"
  count  = var.enable_gateway_tls ? 1 : 0

  acme_email          = var.acme_email
  acme_server         = var.acme_server
  tls_solver          = var.tls_solver
  cluster_issuer_name = var.cluster_issuer_name

  gateway_implementation             = var.gateway_implementation
  customer_gateway                   = var.customer_gateway
  gateway_hostname                   = var.gateway_hostname
  route_namespaces                   = var.workload_namespaces
  max_request_body_mib               = var.max_request_body_mib
  gateway_infrastructure_annotations = var.gateway_infrastructure_annotations
  data_plane_load_balancer_ip        = var.gateway_load_balancer_ip

  dns01_azure = local.dns01 && var.enable_dns ? {
    subscription_id     = module.dns[0].subscription_id
    resource_group_name = module.dns[0].resource_group_name
    hosted_zone_name    = module.dns[0].domain
    client_id           = module.dns[0].dns01_client_id
  } : null
}

# The secret store is installed with the key vault, whatever serves inbound traffic: workloads
# need their secrets from the first one on.
module "external_secrets" {
  source = "../../../modules/cluster-addons/external-secrets"
  count  = var.enable_secrets_backend ? 1 : 0

  cluster_secret_store_name = var.cluster_secret_store_name
  azure_key_vault_store = {
    vault_uri = module.secrets_backend[0].vault_uri
    client_id = module.secrets_backend[0].client_id
    tenant_id = module.secrets_backend[0].tenant_id
  }
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

# The Azure role definition names this stack's enabled modules assign: the one list a bootstrap's
# RBAC-Administrator ABAC condition needs. The bootstrap calls modules/assigned-roles itself before
# any state exists; the stack exposes the same answer as the `assigned_role_names` output.
module "assigned_roles" {
  source = "../../../modules/assigned-roles"

  enable_cluster            = var.enable_cluster
  enable_container_registry = var.enable_container_registry
  enable_dns                = var.enable_dns
  enable_secrets_backend    = var.enable_secrets_backend
}
