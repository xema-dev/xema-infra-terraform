output "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore (every ExternalSecret's secretStoreRef.name)."
  value       = var.cluster_secret_store_name
}

output "namespace" {
  description = "Namespace the operator runs in."
  value       = helm_release.external_secrets.namespace
}
