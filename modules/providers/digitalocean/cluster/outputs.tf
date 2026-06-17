output "cluster_id" {
  description = "DOKS cluster uuid (use as the import id)."
  value       = digitalocean_kubernetes_cluster.this.id
}

output "endpoint" {
  description = "Kubernetes API server URL."
  value       = digitalocean_kubernetes_cluster.this.endpoint
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig YAML."
  value       = digitalocean_kubernetes_cluster.this.kube_config[0].raw_config
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = digitalocean_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "token" {
  description = "Short-lived API token for the cluster."
  value       = digitalocean_kubernetes_cluster.this.kube_config[0].token
  sensitive   = true
}

output "vpc_id" {
  description = "VPC uuid the cluster lives in."
  value       = digitalocean_kubernetes_cluster.this.vpc_uuid
}
