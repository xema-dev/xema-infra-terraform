output "bucket" {
  description = "Storage account name holding Terraform state."
  value       = azurerm_storage_account.this.name
}

output "endpoint" {
  description = "Primary Blob endpoint URL of the state account."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container" {
  description = "Blob container holding the state objects."
  value       = azurerm_storage_container.this.name
}

output "resource_group_name" {
  description = "Resource group holding the account (created or supplied)."
  value       = local.resource_group_name
}

output "backend_config_hint" {
  description = <<-EOT
    Ready-to-adapt `backend "azurerm" {}` block for pointing another root at this
    account. Replace <key> with the per-root state path. Authenticate with
    Entra ID (`use_azuread_auth = true`, the running principal needs Storage
    Blob Data Contributor on the container) — never a committed account key.
    Locking is native (blob leases); no lock table is needed.
  EOT
  value       = <<-EOT
    terraform {
      backend "azurerm" {
        resource_group_name  = "${local.resource_group_name}"
        storage_account_name = "${azurerm_storage_account.this.name}"
        container_name       = "${azurerm_storage_container.this.name}"
        key                  = "<key>"        # e.g. "xema-substrate/terraform.tfstate"
        use_azuread_auth     = true
      }
    }
  EOT
}
