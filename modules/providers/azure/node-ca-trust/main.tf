# Pure mapping (no provider, no resources): PEM CA certificates -> the AKS
# custom CA trust field. Kept apart from providers/azure/cluster so its rules
# are testable without a provider on Terraform 1.6 and OpenTofu.
output "custom_ca_trust_certificates_base64" {
  description = "azurerm_kubernetes_cluster.custom_ca_trust_certificates_base64: each PEM trimmed and base64-encoded, or null when there are none (so a cluster without custom CAs plans no change)."
  value       = length(var.certificates) == 0 ? null : [for c in var.certificates : base64encode(trimspace(c))]
}
