output "storage_class_name" {
  description = "Name of the created ReadWriteMany StorageClass (use as its import id)."
  value       = kubernetes_storage_class_v1.this.metadata[0].name
}

output "release_name" {
  description = "Helm release name of the NFS provisioner; null when manage_provisioner_chart = false (provisioner consumed, not managed)."
  value       = one(helm_release.this[*].name)
}

output "namespace" {
  description = "Namespace the NFS provisioner release is installed into; null when manage_provisioner_chart = false."
  value       = one(helm_release.this[*].namespace)
}
