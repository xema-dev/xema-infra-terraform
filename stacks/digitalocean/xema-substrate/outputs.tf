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
  description = "Extension-claimed object-storage bucket names keyed by \"<biome>/<claim>\"."
  value       = { for k, m in module.extension_bucket : k => m.bucket }
}

output "extension_databases" {
  description = "Extension-claimed dedicated database names keyed by \"<biome>/<claim>\"."
  value       = { for k, r in digitalocean_database_db.extension : k => r.name }
}
