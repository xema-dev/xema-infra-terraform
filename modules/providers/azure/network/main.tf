locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  # The private DNS zone Azure registers each private-link service under. A
  # CLOSED map: a service not listed here has no private endpoint in this
  # module set, and asking for one is refused at plan time (variables.tf).
  private_link_zones = {
    blob  = "privatelink.blob.core.windows.net"
    redis = "privatelink.redis.cache.windows.net"
    vault = "privatelink.vaultcore.azure.net"
  }
}

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = "${var.name}-rg"
  location = var.region
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# One VNet, four subnets — each with ONE purpose:
#   aks                nodes (the cluster module consumes it; it creates no network)
#   postgres           DELEGATED to PostgreSQL Flexible Server (VNet injection)
#   private-endpoints  the private endpoints of every other backing service
#   management         the management runner — the one place inside the network
#                      an operator (or the customer, after handoff) runs
#                      Terraform and the deployment engine from
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = var.region
  resource_group_name = local.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_prefix]
}

resource "azurerm_subnet" "postgres" {
  name                 = "postgres"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.postgres_subnet_prefix]

  delegation {
    name = "postgresql-flexible-server"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoint_subnet_prefix]
}

resource "azurerm_subnet" "management" {
  name                 = "management"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.management_subnet_prefix]
}

# ---------------------------------------------------------------------------
# Private DNS. One zone per private-link service, linked to the VNet, so a
# private endpoint's A record resolves for every workload in it — the AKS nodes
# and the management runner alike — with no custom DNS server.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "this" {
  for_each = toset(var.private_link_services)

  name                = local.private_link_zones[each.value]
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = azurerm_private_dns_zone.this

  name                = "${var.name}-${each.key}"
  private_dns_zone_id = each.value.id
  virtual_network_id  = azurerm_virtual_network.this.id
  tags                = var.tags
}
