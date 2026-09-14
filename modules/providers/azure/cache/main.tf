locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  family = var.sku == "Premium" ? "P" : "C"
}

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = "${var.name}-rg"
  location = var.region
  tags     = var.tags
}

resource "azurerm_redis_cache" "this" {
  name                = var.name
  location            = var.region
  resource_group_name = local.resource_group_name
  tags                = var.tags

  sku_name      = var.sku
  family        = local.family
  capacity      = var.capacity
  redis_version = var.redis_version

  # TLS only: the plaintext port stays off and the contract's `port` is the
  # TLS port.
  non_ssl_port_enabled          = false
  minimum_tls_version           = "1.2"
  public_network_access_enabled = var.public_network_access_enabled

  lifecycle {
    precondition {
      condition     = var.sku != "Premium" || var.capacity >= 1
      error_message = "Premium caches start at capacity 1 (P1)."
    }
  }
}
