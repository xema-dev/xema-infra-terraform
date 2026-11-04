output "namespace" {
  description = "Namespace cert-manager is installed into; its Issuers and Certificates are created after this release."
  value       = helm_release.this.namespace
}

output "gateway_api_enabled" {
  description = "Whether cert-manager runs with its Gateway API support (enableGatewayAPI)."
  value       = var.gateway_api
}
