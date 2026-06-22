output "orchestrator_pvc_name" {
  description = "PVC the orchestrator mounts RW (set as the helm claimName)."
  value       = kubernetes_persistent_volume_claim.orchestrator.metadata[0].name
}

output "workers_pvc_name" {
  description = "PVC workers mount RO (must equal xema-pool-<SHARED_TEMPLATES_POOL_SLUG>)."
  value       = kubernetes_persistent_volume_claim.workers.metadata[0].name
}

output "shared_templates_pool_slug" {
  description = "Slug to set as SHARED_TEMPLATES_POOL_SLUG on workspace-storage-pool-api (derived from the workers PVC name: strip the `xema-pool-` prefix)."
  value       = replace(var.workers_pvc_name, "xema-pool-", "")
}
