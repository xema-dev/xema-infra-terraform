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

# Premium is the SKU that supports private endpoints, and the registry has no
# public endpoint: the stack composes the endpoint with
# providers/azure/private-endpoint (this module knows nothing about networks).
# Admin credentials stay off; access is by Entra identity and role only.
resource "azurerm_container_registry" "this" {
  name                = var.name
  location            = var.region
  resource_group_name = local.resource_group_name
  tags                = var.tags

  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
}

# AcrPull only. The principal that PUSHES images (a CI identity) is the
# consumer's own: it grants AcrPush to that principal itself.
resource "azurerm_role_assignment" "pull" {
  for_each = var.pull_principal_ids

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = each.value

  # The identity is a managed identity created moments earlier; skipping the
  # directory lookup avoids a replication-delay failure on first apply.
  skip_service_principal_aad_check = true
}
