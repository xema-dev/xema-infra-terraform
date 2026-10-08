# All cloud-infra outputs are null when their module is disabled (consumed from
# a separate Terraform). one(module.x[*].y) yields the value when enabled, else null.

output "cluster_id" {
  description = "DOKS cluster uuid when this stack created it; null when consumed."
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
  description = "VPC uuid of the created cluster; null when consumed."
  value       = one(module.cluster[*].vpc_id)
}

output "postgres_host" {
  description = "Created managed-Postgres private host (public fallback); null when consumed."
  value       = one(module.postgres[*].host)
}

output "postgres_port" {
  description = "Created managed-Postgres port; null when consumed."
  value       = one(module.postgres[*].port)
}

output "postgres_uri" {
  description = "Created managed-Postgres admin connection URI; null when consumed."
  value       = one(module.postgres[*].uri)
  sensitive   = true
}

output "dns_domain" {
  description = "The managed DNS zone apex; null when DNS is managed elsewhere."
  value       = one(module.dns[*].domain)
}

output "dns_record_ids" {
  description = "Provider DNS record ids keyed by the merged record key; null when DNS disabled."
  value       = one(module.dns[*].record_ids)
}

output "storage_class_name" {
  description = "Name of the ReadWriteMany StorageClass; null when disabled."
  value       = one(module.rwx_storage[*].storage_class_name)
}

output "workload_namespaces" {
  description = "The set of workload namespaces ensured to exist; null when disabled."
  value       = one(module.workload_namespaces[*].namespaces)
}

output "postgres_databases" {
  description = "The databases ensured on the created cluster (var.platform_databases, verbatim); null when consumed."
  value       = var.enable_managed_postgres ? var.platform_databases : null
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
  description = "Extension-claimed object-storage bucket names keyed by \"<extension>/<claim>\"."
  value       = { for k, m in module.extension_bucket : k => m.bucket }
}

output "extension_databases" {
  description = "Extension-claimed dedicated database names keyed by \"<extension>/<claim>\"."
  value       = { for k, r in digitalocean_database_db.extension : k => r.name }
}

# The BINDING CONTRACT: the one map a consumer reads to bind itself to this
# substrate. The key shape is IDENTICAL to the Azure stack's (docs/CONTRACTS.md
# § Binding contract) so a consumer binds the same way on every cloud; a key
# is null when its area is disabled, consumed elsewhere, or not modelled on
# this cloud (this stack derives no deployment_name, has no environment axis,
# no platform object storage, no secrets backend, no cache and no gateway
# addon, so those keys are always null here). Only non-secret facts live here
# — the credentials are the sensitive outputs above, read separately on
# purpose.
output "deployer_kubeconfig" {
  description = "Kubeconfig for the deployer ServiceAccount — the value a deployment's kubeconfigRef names. A credential and an OPERATOR step: `tofu output -raw deployer_kubeconfig` into the secret store whatever runs helm reads. Null when enable_deployer_identity = false."
  value       = one(module.deployer_identity[*].deployer_kubeconfig)
  sensitive   = true
}

output "substrate" {
  description = "Non-secret facts a consumer binds to, in one map with the cross-cloud key shape documented in docs/CONTRACTS.md. Every value is null when its area is disabled, consumed elsewhere, or not modelled on DigitalOcean."
  value = {
    deployment_name = null
    environment     = null
    region          = var.region
    tenant_id       = null

    cluster_name                = var.cluster_name != "" ? var.cluster_name : null
    cluster_resource_group_name = null
    oidc_issuer_url             = null
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
    postgres_app_role         = null
    postgres_provisioner_role = null
    postgres_databases        = var.enable_managed_postgres ? var.platform_databases : null

    blob_account          = null
    blob_endpoint         = null
    blob_container_prefix = null

    key_vault_name    = null
    key_vault_uri     = null
    secret_store_name = null
    secret_stores     = null

    redis_host = null
    redis_port = null

    dns_zone         = one(module.dns[*].domain)
    dns_name_servers = null

    gateway = null

    keycloak_url = var.enable_identity_realm ? var.keycloak_url : null
    realm_name   = var.enable_identity_realm ? var.realm_name : null
  }
}
