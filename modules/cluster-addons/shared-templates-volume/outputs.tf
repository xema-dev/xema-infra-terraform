output "owner_pvc_name" {
  description = "The claim the owning workload mounts (read-write), in owner_namespace."
  value       = kubernetes_persistent_volume_claim.owner.metadata[0].name
}

output "consumer_pvc_names" {
  description = "The claim each consumer workload mounts, keyed by namespace."
  value       = { for ns, pvc in kubernetes_persistent_volume_claim.consumer : ns => pvc.metadata[0].name }
}

output "persistent_volume_names" {
  description = "Every cluster-scoped PersistentVolume this module created: the owner's, then one per consumer namespace."
  value = concat(
    [kubernetes_persistent_volume.owner.metadata[0].name],
    [for pv in kubernetes_persistent_volume.consumer : pv.metadata[0].name],
  )
}
