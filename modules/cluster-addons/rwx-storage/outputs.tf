output "storage_class_name" {
  description = "Name of the created ReadWriteMany StorageClass (use as its import id)."
  value       = kubernetes_storage_class.this.metadata[0].name
}

output "release_name" {
  description = "Helm release name of the NFS provisioner."
  value       = helm_release.this.name
}

output "namespace" {
  description = "Namespace the NFS provisioner release is installed into."
  value       = helm_release.this.namespace
}
