output "bucket" {
  description = "Storage account name (the contract's bucket)."
  value       = azurerm_storage_account.this.name
}

output "endpoint" {
  description = "Primary Blob endpoint URL (e.g. https://<name>.blob.core.windows.net/). Not S3-compatible — the platform's Azure blob adapter targets it."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "account_name" {
  description = "Storage account name (alias of bucket, named for Azure readers)."
  value       = azurerm_storage_account.this.name
}

output "account_id" {
  description = "Storage account resource id (use as the import id)."
  value       = azurerm_storage_account.this.id
}

output "primary_blob_endpoint" {
  description = "Primary Blob endpoint URL (alias of endpoint, named for Azure readers)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_access_key" {
  description = "Primary account access key (what the platform blob adapter authenticates with while shared_access_key_enabled). Treat as a credential."
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "container_names" {
  description = "Names of the containers pre-created here."
  value       = [for c in azurerm_storage_container.this : c.name]
}

output "resource_group_name" {
  description = "Resource group holding the account (created or supplied)."
  value       = local.resource_group_name
}
