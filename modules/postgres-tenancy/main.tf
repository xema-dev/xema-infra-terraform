# Databases, login roles, grants and EXTENSIONS inside a PostgreSQL server this
# module does not own.
#
# WHY IT IS SEPARATE FROM THE managed-postgres MODULES
#
#   `providers/<cloud>/managed-postgres` CREATES a server and does its tenancy
#   through the cloud's control plane (an `azurerm_postgresql_flexible_server_
#   database`, a `digitalocean_database_db`). A server the consumer already has
#   — a box's Postgres, a Flexible Server another team's Terraform owns, a
#   cluster shared with other products — has no control plane to reach, so its
#   tenancy is done INSIDE the server, over SQL, by the postgresql provider.
#
#   That is the case this fleet is mostly in, and it is the case that had no
#   module: the databases were created by a generated SQL file somebody ran by
#   hand with a superuser door, and the one extension a database owner cannot
#   create was created with a shell on the host.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   No server. No firewall, no parameter, no backup policy, no sizing — those
#   belong to whoever owns the server, and a module that set them would be
#   claiming an ownership it does not have. It takes the connection as the
#   provider configuration the ROOT supplies (CONVENTIONS.md) and touches
#   nothing outside the objects named in its inputs.

locals {
  # `role => set(database)` flattened to one entry per grant, each carrying the
  # privilege set that grant must hold.
  #
  # THE OWNER'S SET IS NOT `CONNECT`, AND ASSUMING IT WAS IS A MEASURED DEFECT.
  # This provider's `postgresql_grant` is DECLARATIVE: it sets exactly the
  # privileges listed and revokes the rest. So granting an owner CONNECT alone
  # takes CREATE and TEMPORARY away from it — and an owner that cannot CREATE on
  # its own database cannot create a schema or a table, which is every migration
  # this platform runs. Proven against PostgreSQL 18.6: the incumbent bootstrap
  # SQL leaves `<role>=CTc/<role>`, this module left `<role>=c/<role>`.
  connect_grants = merge([
    for role, databases in var.connect_grants : {
      for database in databases : "${role}/${database}" => {
        role     = role
        database = database
        privileges = (
          try(var.database_owners[database], null) == role
          ? ["CONNECT", "TEMPORARY", "CREATE"]
          : ["CONNECT"]
        )
      }
    }
  ]...)

  # `database => set(extension)` flattened the same way.
  extensions = merge([
    for database, names in var.extensions : {
      for name in names : "${database}/${name}" => { database = database, name = name }
    }
  ]...)
}

# Cross-input guards. A `validation` block sees one variable, so every
# requirement that spans two fails here, naming the input, before a single
# object is created — an apply that creates three of five databases and then
# refuses is the half-applied state this repository's migrations rule is about.
resource "terraform_data" "input_guards" {
  lifecycle {
    precondition {
      condition     = alltrue([for database in keys(var.extensions) : contains(var.databases, database)])
      error_message = "extensions names a database this module does not manage. Add it to `databases`, or declare the extension where that database IS managed — creating an extension in somebody else's database is a write outside this module's stated reach."
    }
    precondition {
      condition     = alltrue([for database in keys(var.database_owners) : contains(var.databases, database)])
      error_message = "database_owners names a database this module does not manage."
    }
    precondition {
      condition     = alltrue([for role in values(var.database_owners) : contains(var.roles, role)])
      error_message = "database_owners names a role this module does not manage. A database owned by a role nothing here creates is a database nothing can migrate."
    }
    precondition {
      condition     = alltrue([for role in keys(var.connect_grants) : contains(var.roles, role)])
      error_message = "connect_grants names a role this module does not manage."
    }
    precondition {
      condition = alltrue([
        for _, databases in var.connect_grants : alltrue([
          for database in databases : contains(var.databases, database)
        ])
      ])
      error_message = "connect_grants names a database this module does not manage."
    }
  }
}

resource "random_password" "role" {
  for_each = var.roles

  length  = 32
  special = false
}

resource "postgresql_role" "this" {
  for_each = var.roles

  name             = each.value
  login            = true
  password         = random_password.role[each.value].result
  create_database  = try(var.role_options[each.value].create_database, false)
  connection_limit = try(var.role_options[each.value].connection_limit, -1)
}

resource "postgresql_database" "this" {
  for_each = var.databases

  name  = each.value
  owner = try(postgresql_role.this[var.database_owners[each.value]].name, null)

  # The server's own defaults decide encoding and collation. A module that
  # pinned them would refuse to ADOPT any existing database whose locale
  # differs — and adoption is most of what this module is for.
  lifecycle {
    ignore_changes = [encoding, lc_collate, lc_ctype, template]
  }
}

# An empty privilege set on the `public` pseudo-role is this provider's spelling
# of REVOKE ALL. It is what makes a database on a shared server a boundary
# rather than a name.
resource "postgresql_grant" "revoke_public" {
  for_each = var.revoke_public_connect ? var.databases : toset([])

  database    = postgresql_database.this[each.value].name
  role        = "public"
  object_type = "database"
  privileges  = []
}

resource "postgresql_grant" "connect" {
  for_each = local.connect_grants

  database    = postgresql_database.this[each.value.database].name
  role        = postgresql_role.this[each.value.role].name
  object_type = "database"
  privileges  = each.value.privileges

  depends_on = [postgresql_grant.revoke_public]
}

# The step that used to be a superuser and a shell. `vector` is not a trusted
# extension, so a database owner cannot create it; this runs as the credential
# the root configured the provider with.
resource "postgresql_extension" "this" {
  for_each = local.extensions

  name     = each.value.name
  database = postgresql_database.this[each.value.database].name

  # Dropping an extension takes the objects that depend on it — an index, a
  # column type. Removing a name from `extensions` therefore leaves the
  # extension in place and reports the drift rather than destroying data; a
  # deliberate removal is an explicit operator action against the server.
  drop_cascade = false
}
