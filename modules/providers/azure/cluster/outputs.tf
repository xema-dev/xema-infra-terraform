output "cluster_id" {
  description = "AKS cluster resource id (use as the import id)."
  value       = azurerm_kubernetes_cluster.this.id
}

output "endpoint" {
  description = "Kubernetes API server URL."
  # `kube_config` is a sensitive block in azurerm, so everything read from it is
  # sensitive-derived — including the host, which the cluster contract
  # (docs/CONTRACTS.md) declares NON-secret: it is the public API address the
  # kubeconfig itself names. OpenTofu's `validate` refuses a root output that
  # derives from a sensitive value without `sensitive = true`; HashiCorp
  # Terraform raises the same error, one step later, at plan. `nonsensitive`
  # is the explicit, both-engine statement that this one field is not the
  # credential its container is. Found by the OpenTofu validate leg in CI.
  value = nonsensitive(azurerm_kubernetes_cluster.this.kube_config[0].host)
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig YAML."
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "token" {
  description = "Always \"\": AKS issues client-certificate credentials (see client_certificate / client_key), not a bearer token. Kept for the cluster contract."
  value       = ""
  sensitive   = true
}

output "client_certificate" {
  description = "Base64-encoded client certificate for the kubernetes/helm providers (AKS's substitute for a token)."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Base64-encoded client key for the kubernetes/helm providers."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].client_key
  sensitive   = true
}

output "vpc_id" {
  description = "Virtual network id the cluster lives in."
  value       = azurerm_virtual_network.this.id
}

output "delegated_subnet_id" {
  description = "Id of the subnet delegated to PostgreSQL Flexible Server (feed to providers/azure/managed-postgres)."
  value       = azurerm_subnet.postgres.id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster, for federated (workload identity) credentials."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_identity_id" {
  description = "Object (principal) id of the kubelet identity — grant it AcrPull etc."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "cluster_identity_principal_id" {
  description = "Principal id of the cluster's user-assigned identity."
  value       = azurerm_user_assigned_identity.cluster.principal_id
}

output "resource_group_name" {
  description = "Resource group holding the cluster and its network (created or supplied)."
  value       = local.resource_group_name
}

output "node_resource_group" {
  description = "The auto-created resource group holding the AKS node resources."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace id; null when enable_log_analytics = false."
  value       = one(azurerm_log_analytics_workspace.this[*].id)
}
