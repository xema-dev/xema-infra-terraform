output "namespaces" {
  description = "The set of namespaces ensured to exist."
  value       = toset([for ns in kubernetes_namespace.this : ns.metadata[0].name])
}
