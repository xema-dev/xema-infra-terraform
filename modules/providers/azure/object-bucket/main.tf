locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  public_read = var.acl == "public-read"
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

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = local.public_read
  public_network_access_enabled   = var.public_network_access_enabled
  shared_access_key_enabled       = var.shared_access_key_enabled

  # Opt-in only: absent (default) leaves the account's rules as Azure sets them.
  dynamic "network_rules" {
    for_each = var.network_rules == null ? [] : [var.network_rules]
    content {
      default_action             = "Deny"
      bypass                     = ["None"]
      virtual_network_subnet_ids = network_rules.value.virtual_network_subnet_ids
    }
  }

  lifecycle {
    precondition {
      condition     = var.network_rules == null || var.public_network_access_enabled
      error_message = "network_rules (VNet service endpoints) needs public_network_access_enabled = true: storage evaluates service-endpoint rules on its public endpoint."
    }
  }

  blob_properties {
    versioning_enabled = var.versioning
  }
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = local.public_read ? "blob" : "private"
}
