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
  description = "Per boundary: its namespaces, its vault and the identity client id of each namespace's store. Non-secret."
  value = { for k, b in module.boundaries.boundaries : k => {
    namespaces   = b.namespaces
    key_vault_id = b.key_vault_id
    client_ids   = { for ns in b.namespaces : ns => azurerm_user_assigned_identity.store["${k}/${ns}"].client_id }
  } }
}

output "required_role_assignments" {
  description = "Every role assignment this module creates when its own gate is on, whatever manage_role_assignments says (principal_type is what the resource sets, null when it sets none): {scope, role_definition_name, principal_id, principal_type}. Grant them elsewhere when manage_role_assignments = false."
  value       = local.required_role_assignments
}

output "role_assignments_created" {
  description = "How many azurerm_role_assignment resources this module plans: 0 when manage_role_assignments = false. Lets a caller prove the flag reached the module."
  value       = length(azurerm_role_assignment.store)
}
