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

  cluster_name = var.cluster_name != "" ? var.cluster_name : "${local.dep}-aks"
  cluster_resource_group_name = (var.cluster_resource_group_name != "" ? var.cluster_resource_group_name
    : var.resource_group_name != "" ? var.resource_group_name
  : (var.network != null ? var.network.resource_group_name : "${local.dep}-rg"))
  # The four GLOBALLY-unique names: derived unless overridden (variables.tf).
  postgres_name         = var.postgres_server_name != "" ? var.postgres_server_name : "${local.dep}-pg"
  key_vault_name        = var.key_vault_name != "" ? var.key_vault_name : "${local.dep}-kv"
  blob_account_name     = var.storage_account_name != "" ? var.storage_account_name : "${local.compact}blob"
  redis_name            = var.redis_cache_name != "" ? var.redis_cache_name : "${local.dep}-redis"
  realm_name            = local.dep
  realm_display_name    = var.realm_display_name != "" ? var.realm_display_name : local.dep
  blob_container_prefix = var.blob_container_prefix != "" ? var.blob_container_prefix : local.dep

  tags = merge(
    {
      deployment  = local.dep
      environment = var.environment
      managed-by  = "terraform"
    },
    var.tags,
  )

  # The roster of workload namespaces is an INPUT (var.workload_namespaces):
  # which namespaces a deployment runs in is a fact the consumer derives from
  # what it deploys, never something the substrate knows. The same holds for the
  # databases: var.platform_databases carries the logical names, and the ONE
  # rewrite this stack applies is the Postgres-identifier prefix below.
  postgres_databases = toset([for d in var.platform_databases : "${local.pg}_${d}"])

  # Two roles: the application role, and a provisioner role that may CREATE
  # databases at runtime (for a consumer that provisions per-tenant databases).
  postgres_app_role         = local.pg
  postgres_provisioner_role = "${local.pg}_provisioner"
  postgres_roles            = [local.postgres_app_role, local.postgres_provisioner_role]
  postgres_role_options = {
    (local.postgres_provisioner_role) = { create_database = true }
  }
  # ONE ownership rule, for a created server and a consumed one alike: the app
  # role OWNS every database it is given, so a migration running as it can
  # CREATE in schema `public` (on PostgreSQL 15+ only the owner can). The
  # provisioner reaches them with CONNECT.
  postgres_database_owners = { for db in local.postgres_databases : db => local.postgres_app_role }

  blob_containers = [for c in var.blob_containers : "${local.blob_container_prefix}-${c}"]

  dns01 = var.tls_solver == "dns01-azure"

  # Irreversible / cost-bearing safety knobs follow the environment.
  key_vault_purge_protection = var.environment == "prod"
  postgres_backup_retention  = var.environment == "prod" ? 35 : 7

  # ---------------------------------------------------------------------------
  # Cluster facts: from the created cluster, else the existing one read by name.
  # ---------------------------------------------------------------------------
  needs_kube          = var.enable_rwx_storage || var.enable_workload_namespaces || var.enable_ingress_tls || var.enable_deployer_identity
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

  # The network is the foundation's, whether or not this stack creates the cluster.
  vpc_id              = var.network == null ? "" : var.network.vnet_id
  delegated_subnet_id = var.network == null ? "" : var.network.postgres_subnet_id

  # Local (certificate) accounts off: the kubernetes/helm providers can no
  # longer present the cluster's client certificate and authenticate through
  # kubelogin with the caller's Azure CLI identity instead (providers.tf).
  kube_entra_auth = var.cluster_entra_rbac != null ? var.cluster_entra_rbac.local_account_disabled : false

  private_backing_services = var.backing_services_network_access == "private"
  # Which private endpoints this stack needs: one per CREATED backing service.
  # WANTED is what the input guard checks; BUILT is the same list only once a
  # network exists, so a root that omits `network` gets the guard's message
  # instead of a null-attribute error.
  private_endpoint_services_wanted = compact(concat(local.private_backing_services ? [
    var.enable_object_storage ? "blob" : "",
    var.enable_cache ? "redis" : "",
    var.enable_secrets_backend ? "vault" : "",
    ] : [], [
    var.enable_managed_postgres && var.postgres_network_access == "private_endpoint" ? "postgres" : "",
  ]))
  private_endpoint_services = var.network == null ? [] : local.private_endpoint_services_wanted

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
  # A private-endpoint server keeps its public NAME: Azure answers it with a
  # CNAME into privatelink.postgres.database.azure.com, which resolves to the
  # endpoint's private address wherever that zone is resolvable.
  postgres_created_host = (var.postgres_network_access == "private"
    ? local.postgres_private_dns_zone_name
  : "${local.postgres_name}.postgres.database.azure.com")

  pg_host        = var.enable_managed_postgres ? local.postgres_created_host : var.existing_postgres_host
  pg_admin_login = var.enable_managed_postgres ? "pgadmin" : var.existing_postgres_admin_login
  pg_admin_password = (var.enable_managed_postgres
    ? (var.postgres_administrator_password != "" ? var.postgres_administrator_password : one(random_password.postgres_admin[*].result))
  : one(data.azurerm_key_vault_secret.existing_postgres_admin[*].value))

  # Consume mode runs SQL against the existing server only when it has
  # something to ensure there: this deployment's platform_databases tenancy, or
  # an extension managed_databases claim (extensions.tf). Only then is the
  # admin password read — absent both, nothing is read and nothing connects.
  pg_consume_runs_sql = !var.enable_managed_postgres && (length(local.postgres_databases) > 0 || length(local.ext_databases) > 0)

  # The created server's admin password is written into this stack's own vault
  # (module.secrets_backend) under postgres_admin_password_secret_name, which is
  # where a consume-mode instance on the same server reads it from.
  # The NAME is derived apart from the value: it drives a for_each, and a set
  # read off a map whose value is a credential must never pick up its marks.
  pg_admin_password_secret_names = (var.enable_managed_postgres && var.enable_secrets_backend
  ? [var.postgres_admin_password_secret_name] : [])
  pg_admin_password_secret = { for name in local.pg_admin_password_secret_names : name => local.pg_admin_password }
  ext_db_server_id         = var.enable_managed_postgres ? one(module.postgres[*].cluster_id) : var.existing_postgres_server_id

  # ---------------------------------------------------------------------------
  # Extension claim flattening, keyed by "<extension>/<claim>" so adding/removing
  # an extension only adds/removes its own resources.
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
