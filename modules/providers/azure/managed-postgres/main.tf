locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  private               = var.network_access == "private"
  private_dns_zone_name = var.private_dns_zone_name != "" ? var.private_dns_zone_name : "${var.name}.private.postgres.database.azure.com"

  administrator_password = var.generate_administrator_password ? random_password.administrator[0].result : var.administrator_password
}

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = "${var.name}-rg"
  location = var.region
  tags     = var.tags
}

resource "random_password" "administrator" {
  count = var.generate_administrator_password ? 1 : 0

  length  = 32
  special = false
}

# ---------------------------------------------------------------------------
# Private access: a private DNS zone linked to the clients' VNet. Azure requires
# the link to exist BEFORE a VNet-injected server is created.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "this" {
  count = local.private ? 1 : 0

  name                = local.private_dns_zone_name
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  count = local.private ? 1 : 0

  name                = "${var.name}-link"
  private_dns_zone_id = azurerm_private_dns_zone.this[0].id
  virtual_network_id  = var.vpc_id
  tags                = var.tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.name
  location            = var.region
  resource_group_name = local.resource_group_name
  version             = var.engine_version
  sku_name            = var.size
  storage_mb          = var.storage_mb
  auto_grow_enabled   = var.auto_grow_enabled
  zone                = var.zone != "" ? var.zone : null
  tags                = var.tags

  administrator_login    = var.administrator_login
  administrator_password = local.administrator_password

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  public_network_access_enabled = !local.private
  delegated_subnet_id           = local.private ? var.delegated_subnet_id : null
  private_dns_zone_id           = local.private ? azurerm_private_dns_zone.this[0].id : null

  dynamic "high_availability" {
    for_each = var.node_count == 2 ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]

  lifecycle {
    # Azure picks a zone when none is requested and reports it back; that must
    # not read as drift. The HA standby zone likewise.
    ignore_changes = [zone, high_availability[0].standby_availability_zone]

    precondition {
      condition     = var.generate_administrator_password || var.administrator_password != ""
      error_message = "generate_administrator_password = false requires administrator_password."
    }

    precondition {
      condition     = !local.private || (var.delegated_subnet_id != "" && var.vpc_id != "")
      error_message = "network_access = \"private\" requires both delegated_subnet_id (a subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers) and vpc_id (the VNet to link the private DNS zone to)."
    }
  }
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "this" {
  for_each = local.private ? {} : var.public_firewall_rules

  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = each.value.start_ip_address
  end_ip_address   = each.value.end_ip_address
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = var.databases

  name      = each.value
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------------------------------------------------------------------------
# Roles and grants live INSIDE the server: Azure's control plane has no logical
# role resource, so they go through the postgresql provider, which the stack
# configures against the admin credentials above.
#
# They are NOT implemented here. modules/postgres-tenancy is the one
# implementation of in-server tenancy — the same module a stack uses on a
# server it only consumes — so the PostgreSQL 16 handling it carries (the
# connecting admin granted every managed role; revoke-PUBLIC ordered for a
# clean destroy; a measured provider floor) cannot be fixed in one copy and
# missed in the other. The databases above stay control-plane resources and
# are passed as existing_databases: the tenancy module grants on them and never
# creates, alters or drops them. No owner is set, exactly as before: every role
# gets CONNECT on every database and PUBLIC loses it.
# ---------------------------------------------------------------------------

module "tenancy" {
  source = "../../../postgres-tenancy"
  count  = length(var.roles) > 0 || length(var.databases) > 0 ? 1 : 0

  connecting_role    = var.administrator_login
  databases          = []
  existing_databases = var.databases
  roles              = var.roles
  role_options       = var.role_options
  connect_grants     = { for role in var.roles : role => var.databases }

  depends_on = [azurerm_postgresql_flexible_server_database.this]
}

# The in-server objects moved into module.tenancy with the same keys, so an
# existing state re-addresses them instead of destroying and re-creating roles
# (and rotating their passwords).
moved {
  from = random_password.role
  to   = module.tenancy[0].random_password.role
}

moved {
  from = postgresql_role.this
  to   = module.tenancy[0].postgresql_role.this
}

moved {
  from = postgresql_grant.revoke_public
  to   = module.tenancy[0].postgresql_grant.revoke_public
}

moved {
  from = postgresql_grant.connect
  to   = module.tenancy[0].postgresql_grant.connect
}
