output "ingress_service_name" {
  description = "Name of the ingress controller's LoadBalancer Service (\"<release>-controller\") — resolve its external IP from here for DNS."
  value       = "${helm_release.ingress_nginx.name}-controller"
}

output "ingress_namespace" {
  description = "Namespace the ingress controller runs in."
  value       = helm_release.ingress_nginx.namespace
}

output "ingress_class_name" {
  description = "IngressClass name Ingress resources should reference."
  value       = var.ingress_class_name
}

output "cluster_issuer_name" {
  description = "Name of the ACME ClusterIssuer (for the cert-manager.io/cluster-issuer annotation)."
  value       = var.cluster_issuer_name
}
