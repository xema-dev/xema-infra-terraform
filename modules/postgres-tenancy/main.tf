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

  # Every database this module governs, and the name each is reached by: the
  # ones it CREATES (resolved through the resource, so a grant waits for the
  # CREATE) and the ones a control plane already created (existing_databases),
  # which it grants on and never creates, alters or drops.
  governed_databases = setunion(var.databases, var.existing_databases)
  database_names = merge(
    { for database in var.existing_databases : database => database },
    { for database in var.databases : database => postgresql_database.this[database].name },
  )

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
      condition     = alltrue([for database in keys(var.extensions) : contains(local.governed_databases, database)])
      error_message = "extensions names a database this module does not manage. Add it to `databases`, or declare the extension where that database IS managed — creating an extension in somebody else's database is a write outside this module's stated reach."
    }
    precondition {
      condition     = alltrue([for database in keys(var.database_owners) : contains(var.databases, database)])
      error_message = "database_owners names a database this module does not CREATE. An owner is set by the CREATE (or an adopting import); a database in existing_databases keeps the owner its control plane gave it."
    }
    precondition {
      condition     = alltrue([for role in values(var.database_owners) : contains(var.roles, role)])
      error_message = "database_owners names a role this module does not manage. A database owned by a role nothing here creates is a database nothing can migrate."
    }
    precondition {
      condition     = length(setintersection(var.databases, var.existing_databases)) == 0
      error_message = "A database is in both databases and existing_databases. It is either created here or created elsewhere, never both."
    }
    precondition {
      condition     = alltrue([for role in keys(var.connect_grants) : contains(var.roles, role)])
      error_message = "connect_grants names a role this module does not manage."
    }
    precondition {
      condition = alltrue([
        for _, databases in var.connect_grants : alltrue([
          for database in databases : contains(local.governed_databases, database)
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

# THE CONNECTING ROLE IS GRANTED EVERY MANAGED ROLE, AND ON POSTGRESQL 16+
# NOTHING WORKS WITHOUT IT.
#
# This module runs as a NON-superuser that holds CREATEROLE — the Azure Flexible
# Server admin, and the posture every shared server should have. From
# PostgreSQL 16 such a role receives, for each role it creates, only an
# ADMIN OPTION membership with SET and INHERIT both false
# (`createrole_self_grant` defaults to ''). That membership lets it grant the
# role; it does not let it act AS the role. Two things then go wrong, both
# measured against postgres:16 with a CREATEROLE + CREATEDB login:
#
#   - with cyrilgdn/postgresql 1.22 / 1.23, `CREATE DATABASE … OWNER <role>`
#     refuses: `pq: must be able to SET ROLE "<role>"`;
#   - with 1.24 – 1.27, which work around that by granting and revoking the
#     owner role around the CREATE, the database is created and owned — and
#     then every database-level grant below is SILENTLY A NO-OP. GRANT and
#     REVOKE run as this role, which holds no privilege on a database another
#     role owns, so PostgreSQL emits a warning and changes nothing: PUBLIC
#     keeps `Tc`, the provisioner never receives CONNECT, the apply is green,
#     and every plan after it shows the same in-place drift forever. A tenancy
#     boundary that is reported applied and is not there.
#
# A plain `GRANT <role> TO <connecting role>` — SET defaults to TRUE, and
# INHERIT to the connecting role's own INHERIT attribute (TRUE by default) —
# fixes both: the CREATE may name the owner,
# and a GRANT issued by a member of the owning role is recorded as granted by
# the owner. It widens nothing real — a CREATEROLE role holding ADMIN OPTION on
# a role can already grant it to itself; this states that it does.
#
# `with_admin_option` is false and IGNORED after create, and both are forced:
# the provider reads the membership back as admin = true (it sees the
# bootstrap ADMIN-OPTION row as well), so without the ignore every plan
# replaces this grant; and asking for true is refused outright — "ADMIN option
# cannot be granted back to your own grantor".
resource "postgresql_grant_role" "connecting_role" {
  for_each = var.roles

  role              = var.connecting_role
  grant_role        = postgresql_role.this[each.value].name
  with_admin_option = false

  lifecycle {
    ignore_changes = [with_admin_option]
  }
}

resource "postgresql_database" "this" {
  for_each = var.databases

  name  = each.value
  owner = try(postgresql_role.this[var.database_owners[each.value]].name, null)

  # Naming an owner needs SET on it (above). This is also what orders destroy:
  # a database is dropped while its owner is still reachable.
  depends_on = [postgresql_grant_role.connecting_role]

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
#
# It is ordered AFTER the role grants, not before, and the reason is destroy:
# this provider opens a transaction INSIDE the database to delete a grant. If
# the owner's own grant were removed first, nobody could connect any more —
# PUBLIC is already revoked — and destroy would stop on `permission denied for
# database`, measured. Ordered this way, the PUBLIC revoke is undone while the
# owner still holds CONNECT.
resource "postgresql_grant" "revoke_public" {
  for_each = var.revoke_public_connect ? local.governed_databases : toset([])

  database    = local.database_names[each.value]
  role        = "public"
  object_type = "database"
  privileges  = []

  depends_on = [postgresql_grant.connect]
}

resource "postgresql_grant" "connect" {
  for_each = local.connect_grants

  database    = local.database_names[each.value.database]
  role        = postgresql_role.this[each.value.role].name
  object_type = "database"
  privileges  = each.value.privileges
}

# The step that used to be a superuser and a shell. `vector` is not a trusted
# extension, so a database owner cannot create it; this runs as the credential
# the root configured the provider with.
resource "postgresql_extension" "this" {
  for_each = local.extensions

  name     = each.value.name
  database = local.database_names[each.value.database]

  # Dropping an extension takes the objects that depend on it — an index, a
  # column type. Removing a name from `extensions` therefore leaves the
  # extension in place and reports the drift rather than destroying data; a
  # deliberate removal is an explicit operator action against the server.
  drop_cascade = false
}
