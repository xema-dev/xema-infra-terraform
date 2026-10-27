# Pure mapping (no provider, no resources): the API's private DNS zone setting
# of an AKS cluster. Kept apart from providers/azure/cluster so its rules are
# testable without a provider on Terraform 1.6 and OpenTofu.
output "private_dns_zone_id" {
  description = "azurerm_kubernetes_cluster.private_dns_zone_id: null for a public cluster or when unset (AKS default), else the value."
  value       = var.private_cluster_enabled ? var.private_dns_zone_id : null

  precondition {
    condition     = var.private_dns_zone_id != "None" || (var.private_cluster_enabled && var.public_fqdn_enabled)
    error_message = "private_dns_zone_id = \"None\" needs private_cluster_enabled = true and private_cluster_public_fqdn_enabled = true: with no private DNS zone, the nodes can reach the API only through its public name."
  }
}
