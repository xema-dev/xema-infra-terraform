output "assigned_role_names" {
  description = "Azure role definition names this module assigns. Static: the names this module can assign, whatever the inputs, so a bootstrap's ABAC condition on the role-assignment writer can be derived before any state exists (see modules/assigned-roles)."
  value       = ["Key Vault Secrets User"]
}

output "secret_store_name" {
  description = "Name of the SecretStore in every boundary namespace (every ExternalSecret's secretStoreRef.name, kind SecretStore)."
  value       = var.secret_store_name
}

output "namespace" {
  description = "Namespace the operator runs in."
  value       = helm_release.external_secrets.namespace
}

output "secret_stores" {
  description = "Per boundary: the identity client id, its namespaces and its vault. Non-secret."
  value = { for k, b in module.boundaries.boundaries : k => {
    client_id    = azurerm_user_assigned_identity.boundary[k].client_id
    namespaces   = b.namespaces
    key_vault_id = b.key_vault_id
  } }
}
