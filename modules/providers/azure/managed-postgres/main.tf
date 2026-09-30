locals {
  create_resource_group = var.resource_group_name == ""
  resource_group_name   = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  private = var.network_access == "private"
  # network_access = "private_endpoint" is neither: no public access and no VNet
  # injection. The server is reached through a private endpoint composed OUTSIDE
  # this module (providers/azure/private-endpoint, service "postgres"), in a
  # subnet that needs no delegation.
  private_dns_zone_name = var.private_dns_zone_name != "" ? var.private_dns_zone_name : "${var.name}.private.postgres.database.azure.com"

  # A private server needs a private DNS zone its clients can resolve. By default
  # this module creates one and links it to var.vpc_id. When the network's owner
  # already runs the zone (an enterprise landing zone whose DNS resolves Azure
  # private zones centrally), it is CONSUMED by id instead: this module then
  # creates neither the zone nor the link, and never takes ownership of either.
  create_private_dns_zone = local.private && var.private_dns_zone_id == ""
  private_dns_zone_id     = local.create_private_dns_zone ? one(azurerm_private_dns_zone.this[*].id) : var.private_dns_zone_id

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
  count = local.create_private_dns_zone ? 1 : 0

  name                = local.private_dns_zone_name
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  count = local.create_private_dns_zone ? 1 : 0

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

  public_network_access_enabled = var.network_access == "public"
  delegated_subnet_id           = local.private ? var.delegated_subnet_id : null
  private_dns_zone_id           = local.private ? local.private_dns_zone_id : null

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
      condition     = !local.private || (var.delegated_subnet_id != "" && (var.vpc_id != "" || var.private_dns_zone_id != ""))
      error_message = "network_access = \"private\" requires delegated_subnet_id (a subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers), and either vpc_id (the VNet to link the private DNS zone this module creates) or private_dns_zone_id (an existing zone the network's owner runs)."
    }
  }
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "this" {
  for_each = var.network_access == "public" ? var.public_firewall_rules : {}

  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = each.value.start_ip_address
  end_ip_address   = each.value.end_ip_address
}

# ---------------------------------------------------------------------------
# Databases, roles and grants live INSIDE the server, and are NOT implemented
# here: modules/postgres-tenancy is the one implementation of in-server
# tenancy — the same module a stack uses on a server it only consumes — so a
# created server and a consumed one get ONE rule. The postgresql provider it
# uses is configured by the stack against the admin credentials above.
#
# The databases are created over SQL rather than through Azure's control
# plane, because the rule includes OWNERSHIP: `database_owners` names the role
# that owns each database, so an application migrating as that role can CREATE
# in schema `public` — on PostgreSQL 15+ only the database owner can — with
# Terraform alone. A control-plane database cannot be given an owner by any
# resource this repository uses. Every role in `roles` reaches every database
# (`CONNECT`, or `CONNECT, TEMPORARY, CREATE` for its owner); PUBLIC loses it.
# ---------------------------------------------------------------------------

module "tenancy" {
  source = "../../../postgres-tenancy"
  count  = length(var.roles) > 0 || length(var.databases) > 0 ? 1 : 0

  connecting_role = var.administrator_login
  databases       = var.databases
  database_owners = var.database_owners
  roles           = var.roles
  role_options    = var.role_options
  connect_grants  = { for role in var.roles : role => var.databases }

  depends_on = [
    azurerm_postgresql_flexible_server.this,
    azurerm_postgresql_flexible_server_firewall_rule.this,
  ]
}

# RETIRED, KEPT AS A FENCE — never as a way to create anything (no instance can
# exist: for_each is empty). Until this change the databases were these
# control-plane resources. A state that still holds one would otherwise plan
# its DESTROY, and destroying a Flexible Server database drops it with its
# data. prevent_destroy turns that into a refusal ("Instance cannot be
# destroyed"), and the README's migration — state rm, then import each
# database into module.tenancy[0].postgresql_database.this — re-addresses the
# same database, after which the plan is the owner change, in place.
resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = toset([])

  name      = each.value
  server_id = azurerm_postgresql_flexible_server.this.id

  lifecycle {
    prevent_destroy = true
  }
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
