output "ngf_values" {
  description = "Zero or one Helm values documents (YAML) for the NGINX Gateway Fabric chart."
  value       = local.ngf_values
}

output "cert_manager_values" {
  description = "Zero or one Helm values documents (YAML) for the cert-manager chart."
  value       = local.cert_manager_values
}
