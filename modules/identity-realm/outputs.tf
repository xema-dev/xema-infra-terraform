output "realm_id" {
  description = "The realm id (equal to the realm name; used as the import id for the realm and as a path segment for client/role imports)."
  value       = keycloak_realm.this.id
}

output "client_ids" {
  description = "Provider client uuids keyed by the var.clients key (NOT the OIDC client_id). Used to form client import ids \"<realm>/client/<uuid>\"."
  value       = { for k, c in keycloak_openid_client.this : k => c.id }
}

output "client_secrets" {
  description = "Client secrets keyed by the var.clients key. Empty for PUBLIC clients. Treat as credentials."
  value       = { for k, c in keycloak_openid_client.this : k => c.client_secret }
  sensitive   = true
}
