output "vault_uri" {
  description = "Key Vault base URI (https://<name>.vault.azure.net/) — the ClusterSecretStore's vaultUrl."
  value       = azurerm_key_vault.this.vault_uri
}

output "client_id" {
  description = "Client id of the reader (workload) identity; \"\" when workload_identity.enabled = false."
  value       = var.workload_identity.enabled ? azurerm_user_assigned_identity.reader[0].client_id : ""
}

output "tenant_id" {
  description = "Entra tenant id the vault and the reader identity live in."
  value       = data.azurerm_client_config.current.tenant_id
}

output "key_vault_id" {
  description = "Key Vault resource id (use as the import id)."
  value       = azurerm_key_vault.this.id
}

output "secret_ids" {
  description = "Versionless secret ids keyed by secret name."
  value       = { for k, s in azurerm_key_vault_secret.this : k => s.versionless_id }
}

output "resource_group_name" {
  description = "Resource group holding the vault (created or supplied)."
  value       = local.resource_group_name
}

output "assigned_role_names" {
  description = "Azure role definition names this module assigns. Static: the names this module can assign, whatever the inputs, so a bootstrap's ABAC condition on the role-assignment writer can be derived before any state exists (see modules/assigned-roles)."
  value       = ["Key Vault Secrets Officer", "Key Vault Secrets User"]
}
