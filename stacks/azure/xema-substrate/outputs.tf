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

output "vpc_id" {
  description = "Virtual network id of the created cluster; null when consumed."
  value       = one(module.cluster[*].vpc_id)
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the created or consumed cluster (for federated credentials); null when no cluster facts were needed."
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
  description = "Generated passwords for the derived roles (app + provisioner), keyed by role; null when consumed."
  value       = one(module.postgres[*].role_passwords)
  sensitive   = true
}

output "postgres_databases" {
  description = "The derived platform databases ensured on the created server."
  value       = local.postgres_databases
}

output "postgres_roles" {
  description = "The derived roles ensured on the created server."
  value       = local.postgres_roles
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

output "key_vault_uri" {
  description = "Key Vault URI; null when disabled."
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
  description = "Extension-claimed storage account names keyed by \"<biome>/<claim>\"."
  value       = { for k, m in module.extension_bucket : k => m.bucket }
}

output "extension_databases" {
  description = "Extension-claimed dedicated database names keyed by \"<biome>/<claim>\"."
  value       = { for k, r in azurerm_postgresql_flexible_server_database.extension : k => r.name }
}

# The one map the Helm layer consumes. Only non-secret facts live here — the
# credentials are the sensitive outputs above, read separately on purpose.
output "substrate" {
  description = "Non-secret facts the Helm layer consumes, in one map. Every value is null when its area is disabled or consumed elsewhere."
  value = {
    deployment_name = local.dep
    environment     = var.environment
    region          = var.region
    tenant_id       = one(module.secrets_backend[*].tenant_id)

    cluster_name                = local.cluster_name
    cluster_resource_group_name = var.enable_cluster ? one(module.cluster[*].resource_group_name) : local.cluster_resource_group_name
    oidc_issuer_url             = local.oidc_issuer_url
    storage_class_name          = one(module.rwx_storage[*].storage_class_name)
    namespaces = {
      platform         = local.dep
      shared           = "${local.dep}-shared"
      infra            = "${local.dep}-infra"
      opencode_workers = "${local.dep}-opencode-workers"
      biome_sidecars   = "${local.dep}-biome-sidecars"
    }

    postgres_host             = one(module.postgres[*].host)
    postgres_port             = one(module.postgres[*].port)
    postgres_app_role         = local.postgres_app_role
    postgres_provisioner_role = local.postgres_provisioner_role
    postgres_databases        = local.postgres_databases

    blob_account          = one(module.blob[*].bucket)
    blob_endpoint         = one(module.blob[*].endpoint)
    blob_container_prefix = local.blob_container_prefix

    key_vault_uri              = one(module.secrets_backend[*].vault_uri)
    external_secrets_client_id = one(module.secrets_backend[*].client_id)
    cluster_secret_store_name  = one(module.ingress_tls[*].cluster_secret_store_name)

    redis_host = one(module.cache[*].host)
    redis_port = one(module.cache[*].port)

    dns_zone         = one(module.dns[*].domain)
    dns_name_servers = one(module.dns[*].name_servers)

    ingress = var.enable_ingress_tls ? {
      service_name        = one(module.ingress_tls[*].ingress_service_name)
      namespace           = one(module.ingress_tls[*].ingress_namespace)
      class_name          = one(module.ingress_tls[*].ingress_class_name)
      cluster_issuer_name = one(module.ingress_tls[*].cluster_issuer_name)
    } : null

    keycloak_url = var.enable_identity_realm ? var.keycloak_url : null
    realm_name   = var.enable_identity_realm ? local.realm_name : null
  }
}
