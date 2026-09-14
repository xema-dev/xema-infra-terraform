# Extension / biome substrate claim wiring.
#
# See docs/extensions.md. The claim KIND set is CLOSED — v1 ships three kinds:
#   object_buckets    -> module.extension_bucket (a storage account each)
#   managed_databases -> azurerm_postgresql_flexible_server_database (+ owner
#                        role via the postgresql provider) on the RESOLVED
#                        server (created module.postgres, or the existing one)
#   dns_records       -> merged into module.dns (requires enable_dns)
#
# The flattening locals live in locals.tf (keyed by "<biome>/<claim>").

# One dedicated storage account per object_buckets claim.
module "extension_bucket" {
  source   = "../../../modules/providers/azure/object-bucket"
  for_each = local.ext_buckets

  name       = each.value.name
  region     = var.region
  acl        = each.value.acl
  versioning = each.value.versioning
  tags       = local.tags
}

# One dedicated logical database per managed_databases claim, on the resolved
# server. Additive — it never touches other databases on a shared server.
resource "azurerm_postgresql_flexible_server_database" "extension" {
  for_each = local.ext_databases

  name      = each.value.database
  server_id = local.ext_db_server_id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    precondition {
      condition     = local.ext_db_server_id != ""
      error_message = "Extension managed_databases were declared but no Postgres server is resolved. Set enable_managed_postgres = true, or provide existing_postgres_server_id (plus existing_postgres_host and admin credentials for the owner roles)."
    }
  }
}

# Optional owner role per claim that declares one, granted CONNECT on its
# database; CONNECT is revoked from PUBLIC on every extension database.
resource "random_password" "extension_owner" {
  for_each = { for k, v in local.ext_databases : k => v if v.owner != null }

  length  = 32
  special = false
}

resource "postgresql_role" "extension_owner" {
  for_each = { for k, v in local.ext_databases : k => v if v.owner != null }

  name     = each.value.owner
  login    = true
  password = random_password.extension_owner[each.key].result

  depends_on = [azurerm_postgresql_flexible_server_database.extension]
}

resource "postgresql_grant" "extension_revoke_public" {
  for_each = local.ext_databases

  database    = azurerm_postgresql_flexible_server_database.extension[each.key].name
  role        = "public"
  object_type = "database"
  privileges  = []
}

resource "postgresql_grant" "extension_owner_connect" {
  for_each = { for k, v in local.ext_databases : k => v if v.owner != null }

  database    = azurerm_postgresql_flexible_server_database.extension[each.key].name
  role        = postgresql_role.extension_owner[each.key].name
  object_type = "database"
  privileges  = ["CONNECT"]
}

# Fail fast (rather than silently drop) if a biome claims a DNS record but the
# dns module is disabled for this deployment.
resource "terraform_data" "extension_guards" {
  count = length(local.ext_dns) > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.enable_dns
      error_message = "Extension dns_records were declared but enable_dns = false. Enable the dns module or remove the records (DNS is managed elsewhere for this deployment)."
    }
  }
}
