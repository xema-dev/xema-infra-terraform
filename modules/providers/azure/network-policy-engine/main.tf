# Pure mapping (no provider, no resources): engine -> AKS network_profile fields. Kept apart from
# providers/azure/cluster so it is testable without a provider on Terraform 1.6 and OpenTofu.
output "network_policy" {
  description = "AKS network_profile.network_policy."
  value       = var.engine
}

output "network_data_plane" {
  description = "AKS network_profile.network_data_plane: \"cilium\" for the Cilium engine, else \"azure\"."
  value       = var.engine == "cilium" ? "cilium" : "azure"
}
