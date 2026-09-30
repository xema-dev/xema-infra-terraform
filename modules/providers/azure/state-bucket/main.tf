locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
}

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = "${var.name}-rg"
  location = var.region
  tags     = var.tags
}

resource "azurerm_storage_account" "this" {
  name                = var.name
  location            = var.region
  resource_group_name = local.resource_group_name
  tags                = var.tags

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication

  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true
  # State accounts are always private — never expose Terraform state.
  allow_nested_items_to_be_public = false
  # false: the state is readable only with a Microsoft Entra identity holding a
  # data-plane role (Storage Blob Data Contributor) — no account key exists to
  # leak. The backend must then say use_azuread_auth = true.
  shared_access_key_enabled = var.shared_access_key_enabled

  # Versioning + soft delete are forced on (not optional): they are the
  # recovery mechanism for a corrupted/overwritten state object.
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = var.soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }
}

resource "azurerm_storage_container" "this" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
