output "secret_names" {
  description = "Created Secret names keyed by the input map key (for Helm secretKeyRef wiring)."
  value       = { for k, s in kubernetes_secret_v1.this : k => s.metadata[0].name }
}

output "namespaces" {
  description = "Distinct namespaces the Secrets were created in."
  value       = distinct([for s in values(var.secrets) : s.namespace])
}
