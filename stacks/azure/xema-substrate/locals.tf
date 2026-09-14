locals {
  # ---------------------------------------------------------------------------
  # Derived names. ONE input, every name a function of it.
  #
  # Two spellings, each forced by a namespace that cannot hold the other:
  #   dep     "acme-dev"  — DNS labels: Kubernetes namespaces, Azure resource
  #                         names, the Keycloak realm, the blob container prefix.
  #   pg      "acme_dev"  — Postgres identifiers (databases, roles): an unquoted
  #                         identifier cannot hold a hyphen, so "-" -> "_".
  #   compact "acmedev"   — storage account names: lowercase alphanumerics only.
  # The rewrites are total and injective on the validated input alphabet
  # (single hyphens, never leading/trailing), so no two deployment names
  # collide after either mapping.
  # ---------------------------------------------------------------------------
  dep     = var.deployment_name
  pg      = replace(var.deployment_name, "-", "_")
  compact = replace(var.deployment_name, "-", "")

  cluster_name                = var.cluster_name != "" ? var.cluster_name : "${local.dep}-aks"
  cluster_resource_group_name = var.cluster_resource_group_name != "" ? var.cluster_resource_group_name : "${local.dep}-rg"
  # The four GLOBALLY-unique names: derived unless overridden (variables.tf).
  postgres_name         = var.postgres_server_name != "" ? var.postgres_server_name : "${local.dep}-pg"
  key_vault_name        = var.key_vault_name != "" ? var.key_vault_name : "${local.dep}-kv"
  blob_account_name     = var.storage_account_name != "" ? var.storage_account_name : "${local.compact}blob"
  redis_name            = var.redis_cache_name != "" ? var.redis_cache_name : "${local.dep}-redis"
  realm_name            = local.dep
  realm_display_name    = var.realm_display_name != "" ? var.realm_display_name : "Xema (${local.dep})"
  blob_container_prefix = var.blob_container_prefix != "" ? var.blob_container_prefix : local.dep

  tags = merge(
    {
      deployment  = local.dep
      environment = var.environment
      managed-by  = "terraform"
    },
    var.tags,
  )

  # The namespaces the Helm bring-up expects. Same roles as the DigitalOcean
  # canonical set, spelled from the deployment name instead of hardcoded.
  workload_namespaces = setunion(
    [
      local.dep,
      "${local.dep}-shared",
      "${local.dep}-infra",
      "${local.dep}-opencode-workers",
      "${local.dep}-biome-sidecars",
    ],
    var.extra_workload_namespaces,
  )

  # One database per platform service that owns one, plus the shared biome
  # database and the backing stores that run in-cluster but persist here.
  platform_databases = [
    "${local.pg}_identity_api",
    "${local.pg}_secrets_api",
    "${local.pg}_event_hub_api",
    "${local.pg}_llm_gateway_api",
    "${local.pg}_mcp_gateway_api",
    "${local.pg}_org_database_pool_api",
    "${local.pg}_redis_pool_api",
    "${local.pg}_biomes",
    "${local.pg}_openfga",
    "${local.pg}_temporal",
    "${local.pg}_temporal_visibility",
    "${local.pg}_gitea",
    "${local.pg}_keycloak",
  ]
  postgres_databases = setunion(
    local.platform_databases,
    var.enable_billing_database ? ["${local.pg}_billing_api"] : [],
    var.postgres_extra_databases,
  )

  # The application role, and the provisioner the org-database pool uses to
  # CREATE per-org databases at runtime.
  postgres_app_role         = local.pg
  postgres_provisioner_role = "${local.pg}_provisioner"
  postgres_roles            = [local.postgres_app_role, local.postgres_provisioner_role]
  postgres_role_options = {
    (local.postgres_provisioner_role) = { create_database = true }
  }

  blob_containers = [for c in var.blob_containers : "${local.blob_container_prefix}-${c}"]

  dns01 = var.tls_solver == "dns01-azure"

  # Irreversible / cost-bearing safety knobs follow the environment.
  key_vault_purge_protection = var.environment == "prod"
  postgres_backup_retention  = var.environment == "prod" ? 35 : 7

  # ---------------------------------------------------------------------------
  # Cluster facts: from the created cluster, else the existing one read by name.
  # ---------------------------------------------------------------------------
  needs_kube          = var.enable_rwx_storage || var.enable_workload_namespaces || var.enable_ingress_tls
  needs_cluster_facts = local.needs_kube || var.enable_secrets_backend || (var.enable_dns && local.dns01)

  kube_host = var.enable_cluster ? one(module.cluster[*].endpoint) : try(one(data.azurerm_kubernetes_cluster.existing[*].kube_config[0].host), null)
  kube_client_cert_b64 = (var.enable_cluster
    ? one(module.cluster[*].client_certificate)
  : try(one(data.azurerm_kubernetes_cluster.existing[*].kube_config[0].client_certificate), null))
  kube_client_key_b64 = (var.enable_cluster
    ? one(module.cluster[*].client_key)
  : try(one(data.azurerm_kubernetes_cluster.existing[*].kube_config[0].client_key), null))
  kube_ca_b64 = (var.enable_cluster
    ? one(module.cluster[*].cluster_ca_certificate)
  : try(one(data.azurerm_kubernetes_cluster.existing[*].kube_config[0].cluster_ca_certificate), null))

  # Never null: "" when no cluster facts are needed, so the modules that take it
  # can be given it unconditionally (coalesce(null, "") is an error, not "").
  oidc_issuer_url = (var.enable_cluster
    ? one(module.cluster[*].oidc_issuer_url)
  : (local.needs_cluster_facts ? data.azurerm_kubernetes_cluster.existing[0].oidc_issuer_url : ""))

  vpc_id              = var.enable_cluster ? one(module.cluster[*].vpc_id) : var.existing_vnet_id
  delegated_subnet_id = var.enable_cluster ? one(module.cluster[*].delegated_subnet_id) : var.existing_delegated_subnet_id

  # ---------------------------------------------------------------------------
  # Postgres facts for the postgresql provider and extension claims.
  #
  # The postgresql provider is configured from values the STACK decides — never
  # from module.postgres outputs. The roles and grants live inside that module
  # (the contract puts them there), so a provider fed by its outputs would
  # depend on the module that depends on the provider: a cycle. Host is
  # therefore DERIVED the way Azure derives it — "<server>.<private zone>" for
  # a VNet-injected server, "<server>.postgres.database.azure.com" for a public
  # one — and the admin credentials are minted here and passed IN.
  # ---------------------------------------------------------------------------
  postgres_private_dns_zone_name = "${local.postgres_name}.private.postgres.database.azure.com"
  postgres_created_host = (var.postgres_network_access == "private"
    ? local.postgres_private_dns_zone_name
  : "${local.postgres_name}.postgres.database.azure.com")

  pg_host        = var.enable_managed_postgres ? local.postgres_created_host : var.existing_postgres_host
  pg_admin_login = var.enable_managed_postgres ? "pgadmin" : var.existing_postgres_admin_login
  pg_admin_password = (var.enable_managed_postgres
    ? (var.postgres_administrator_password != "" ? var.postgres_administrator_password : one(random_password.postgres_admin[*].result))
  : var.existing_postgres_admin_password)
  ext_db_server_id = var.enable_managed_postgres ? one(module.postgres[*].cluster_id) : var.existing_postgres_server_id

  # ---------------------------------------------------------------------------
  # Extension claim flattening, keyed by "<biome>/<claim>" so adding/removing a
  # biome only adds/removes its own resources.
  # ---------------------------------------------------------------------------
  ext_buckets = merge([
    for bid, e in var.extensions :
    { for k, v in e.object_buckets : "${bid}/${k}" => v }
  ]...)

  ext_databases = merge([
    for bid, e in var.extensions :
    { for k, v in e.managed_databases : "${bid}/${k}" => v }
  ]...)

  ext_dns = merge([
    for bid, e in var.extensions :
    { for k, v in e.dns_records : "${bid}/${k}" => v }
  ]...)

  ext_dns_records = {
    for k, v in local.ext_dns : k => {
      name  = v.name
      type  = v.type
      value = v.value
      ttl   = v.ttl
    }
  }
}
