# All cloud-infra outputs are null when their module is disabled (consumed from
# a separate Terraform). one(module.x[*].y) yields the value when enabled, else null.

output "cluster_id" {
  description = "AKS cluster resource id when this stack created it; null when consumed."
  value       = one(module.cluster[*].cluster_id)
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL of the created cluster; null when consumed."
  value       = one(module.cluster[*].endpoint)
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig YAML of the created cluster; null when consumed."
  value       = one(module.cluster[*].kubeconfig_raw)
  sensitive   = true
}

output "kubelet_identity_object_id" {
  description = "Object (principal) id of the cluster's kubelet identity — what a role assignment's principal_id takes (e.g. AcrPull on a registry this stack does not own). From the created or the consumed cluster; null when no cluster facts were needed."
  value       = local.kubelet_identity_object_id
}

output "container_registry_login_server" {
  description = "Container registry login server (<name>.azurecr.io); null when enable_container_registry = false."
  value       = one(module.container_registry[*].login_server)
}

output "container_registry_id" {
  description = "Container registry resource id — the scope a consumer grants AcrPush to its own CI principal on; null when enable_container_registry = false."
  value       = one(module.container_registry[*].id)
}

output "vpc_id" {
  description = "Virtual network id this deployment lives in (the foundation's); null when no network was given."
  value       = var.network == null ? null : var.network.vnet_id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the created or consumed cluster (for federated credentials); \"\" when no cluster facts were needed."
  value       = local.oidc_issuer_url
}

output "postgres_host" {
  description = "Created Flexible Server FQDN; null when consumed."
  value       = one(module.postgres[*].host)
}

output "postgres_port" {
  description = "Created Flexible Server port; null when consumed."
  value       = one(module.postgres[*].port)
}

output "postgres_uri" {
  description = "Created Flexible Server admin connection URI; null when consumed."
  value       = one(module.postgres[*].uri)
  sensitive   = true
}

output "postgres_role_passwords" {
  description = "Generated passwords for the derived roles (app + provisioner), keyed by role — on the created server, or on the consumed one when this stack ensures its tenancy there; null otherwise."
  value       = var.enable_managed_postgres ? one(module.postgres[*].role_passwords) : one(module.postgres_tenancy[*].role_passwords)
  sensitive   = true
}

output "postgres_databases" {
  description = "The databases ensured — var.platform_databases after the deployment-name prefix — on the created server, or on the consumed one when this stack ensures its tenancy there; null otherwise."
  value       = var.enable_managed_postgres || length(module.postgres_tenancy) > 0 ? local.postgres_databases : null
}

output "postgres_roles" {
  description = "The derived roles ensured on the created server, or on the consumed one when this stack ensures its tenancy there; null otherwise."
  value       = var.enable_managed_postgres || length(module.postgres_tenancy) > 0 ? local.postgres_roles : null
}

output "dns_domain" {
  description = "The managed DNS zone apex; null when DNS is managed elsewhere."
  value       = one(module.dns[*].domain)
}

output "dns_name_servers" {
  description = "Azure DNS name servers to delegate the apex to; null when DNS is managed elsewhere."
  value       = one(module.dns[*].name_servers)
}

output "dns_record_ids" {
  description = "Provider DNS record ids keyed by the merged record key; null when DNS disabled."
  value       = one(module.dns[*].record_ids)
}

output "blob_account" {
  description = "Storage account name the platform's blob adapter targets; null when disabled."
  value       = one(module.blob[*].bucket)
}

output "blob_endpoint" {
  description = "Primary Blob endpoint of that account; null when disabled."
  value       = one(module.blob[*].endpoint)
}

output "blob_primary_access_key" {
  description = "Primary access key of the blob account; null when disabled."
  value       = one(module.blob[*].primary_access_key)
  sensitive   = true
}

output "operator_vault_name" {
  description = "Operator vault name (derived or overridden via var.operator_vault_name); null when disabled. The operator vault holds break-glass/infra secrets and is never projected into the cluster."
  value       = var.enable_secrets_backend ? module.vault_names.operator : null
}

output "operator_vault_id" {
  description = "Operator vault resource id; null when disabled. Reference the vault by this id rather than building it from operator_vault_name: the id depends on the vault resource, so consumers order after its creation (a name-built id raced vault creation on a fresh apply)."
  value       = one(module.secrets_backend[*].key_vault_id)
}

output "operator_vault_uri" {
  description = "Operator vault URI; null when disabled."
  value       = one(module.secrets_backend[*].vault_uri)
}

output "redis_host" {
  description = "Managed cache hostname; null when disabled."
  value       = one(module.cache[*].host)
}

output "redis_port" {
  description = "Managed cache TLS port; null when disabled."
  value       = one(module.cache[*].port)
}

output "redis_primary_key" {
  description = "Managed cache primary access key; null when disabled."
  value       = one(module.cache[*].primary_key)
  sensitive   = true
}

output "storage_class_name" {
  description = "Name of the ReadWriteMany StorageClass; null when disabled."
  value       = one(module.rwx_storage[*].storage_class_name)
}

# The two in-cluster resource names a consumer's manifests reference. Read from
# the addon's outputs — never from the input — so they are null exactly when
# the resource does not exist (gateway disabled; or, for the store, the secrets
# backend disabled).
output "gateway_parent_refs" {
  description = "The parentRefs HTTPRoutes attach to, one per HTTPS listener, keyed by listener name ({ name, namespace, section_name }); null when enable_gateway_tls = false."
  value       = one(module.gateway_tls[*].gateway_parent_refs)
}

output "cluster_issuer_name" {
  description = "Name of the ACME ClusterIssuer (the cert-manager.io/cluster-issuer annotation value); null when enable_gateway_tls = false."
  value       = one(module.gateway_tls[*].cluster_issuer_name)
}

output "secret_store_name" {
  description = "Name of the SecretStore in every boundary namespace (every ExternalSecret's secretStoreRef.name, kind SecretStore); null when enable_secrets_backend = false."
  value       = one(module.external_secrets[*].secret_store_name)
}

output "secret_stores" {
  description = "Per secret trust boundary: its identity client id, namespaces and its own vault id. Null when enable_secrets_backend = false."
  value       = one(module.external_secrets[*].secret_stores)
}

output "workload_namespaces" {
  description = "The set of workload namespaces ensured to exist; null when disabled."
  value       = one(module.workload_namespaces[*].namespaces)
}

output "realm_id" {
  description = "The managed Keycloak realm id (equal to the realm name); null when disabled."
  value       = one(module.identity_realm[*].realm_id)
}

output "realm_client_secrets" {
  description = "Realm OIDC client secrets keyed by the var.realm_clients key. Empty for PUBLIC clients. Treat as credentials."
  value       = one(module.identity_realm[*].client_secrets)
  sensitive   = true
}

output "extension_buckets" {
  description = "Extension-claimed storage account names keyed by \"<extension>/<claim>\"."
  value       = { for k, m in module.extension_bucket : k => m.bucket }
}

output "extension_databases" {
  description = "Extension-claimed dedicated database names keyed by \"<extension>/<claim>\"."
  value       = { for k, r in azurerm_postgresql_flexible_server_database.extension : k => r.name }
}

# The BINDING CONTRACT: the one map a consumer reads to bind itself to this
# substrate. Same key shape on every cloud (docs/CONTRACTS.md § Binding
# contract); a key is null when its area is disabled, consumed elsewhere, or
# not modelled by this cloud. Only non-secret facts live here — the credentials
# are the sensitive outputs above, read separately on purpose.
output "deployer_kubeconfig" {
  description = "Kubeconfig for the deployer ServiceAccount — the value a deployment's kubeconfigRef names. A credential and an OPERATOR step: `tofu output -raw deployer_kubeconfig` into the secret store whatever runs helm reads. Null when enable_deployer_identity = false."
  value       = one(module.deployer_identity[*].deployer_kubeconfig)
  sensitive   = true
}

output "substrate" {
  description = "Non-secret facts a consumer binds to, in one map with the cross-cloud key shape documented in docs/CONTRACTS.md. Every value is null when its area is disabled or consumed elsewhere."
  value = {
    deployment_name = local.dep
    environment     = var.environment
    region          = var.region
    tenant_id       = one(module.secrets_backend[*].tenant_id)

    cluster_name                = local.cluster_name
    cluster_resource_group_name = var.enable_cluster ? one(module.cluster[*].resource_group_name) : local.cluster_resource_group_name
    oidc_issuer_url             = local.oidc_issuer_url
    kubelet_identity_object_id  = local.kubelet_identity_object_id
    storage_class_name          = one(module.rwx_storage[*].storage_class_name)
    # The roster the consumer supplied, as ensured on the cluster. It carries no
    # roles: which namespace plays which part is the consumer's own knowledge.
    namespaces = one(module.workload_namespaces[*].namespaces)

    # The three facts that identify this cluster whatever anybody calls it:
    # endpoint, sha256 of the DECODED cluster CA, and the UID of kube-system.
    # A context NAME is not among them — it is an alias in a file, so the
    # same cluster under another alias is the same cluster.
    cluster_identity = one(module.deployer_identity[*].cluster_identity)

    postgres_host             = one(module.postgres[*].host)
    postgres_port             = one(module.postgres[*].port)
    postgres_app_role         = var.enable_managed_postgres || length(module.postgres_tenancy) > 0 ? local.postgres_app_role : null
    postgres_provisioner_role = var.enable_managed_postgres || length(module.postgres_tenancy) > 0 ? local.postgres_provisioner_role : null
    postgres_databases        = var.enable_managed_postgres || length(module.postgres_tenancy) > 0 ? local.postgres_databases : null

    blob_account          = one(module.blob[*].bucket)
    blob_endpoint         = one(module.blob[*].endpoint)
    blob_container_prefix = var.enable_object_storage ? local.blob_container_prefix : null

    operator_vault_name = var.enable_secrets_backend ? module.vault_names.operator : null
    operator_vault_uri  = one(module.secrets_backend[*].vault_uri)
    secret_store_name   = one(module.external_secrets[*].secret_store_name)
    secret_stores       = one(module.external_secrets[*].secret_stores)

    redis_host = one(module.cache[*].host)
    redis_port = one(module.cache[*].port)

    container_registry_login_server = one(module.container_registry[*].login_server)
    container_registry_id           = one(module.container_registry[*].id)

    dns_zone         = one(module.dns[*].domain)
    dns_name_servers = one(module.dns[*].name_servers)

    gateway = var.enable_gateway_tls ? {
      parent_refs         = one(module.gateway_tls[*].gateway_parent_refs)
      cluster_issuer_name = one(module.gateway_tls[*].cluster_issuer_name)
    } : null

    keycloak_url = var.enable_identity_realm ? var.keycloak_url : null
    realm_name   = var.enable_identity_realm ? local.realm_name : null
  }
}

output "assigned_role_names" {
  description = "Sorted, de-duplicated Azure role definition names the enabled modules assign (modules/assigned-roles). Derive the RBAC-Administrator ABAC condition of the identity that applies this stack from it."
  value       = module.assigned_roles.assigned_role_names
}
