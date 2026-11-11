variable "databases" {
  description = <<-EOT
    The databases to ensure, by full name. REQUIRED, no default: which databases
    a deployment needs is a fact the consumer derives from what it deploys — this
    module does not know it.

    Each is created if absent and ADOPTED by import if present, so pointing this
    at a server that already carries them is a clean import rather than a
    conflict.
  EOT
  type        = set(string)

  validation {
    condition     = alltrue([for name in var.databases : can(regex("^[a-z_][a-z0-9_]{0,62}$", name))])
    error_message = "Each database name must be lowercase alphanumerics and underscores, starting with a letter or underscore (1-63 chars) — the unquoted-identifier grammar, so nothing here needs quoting downstream."
  }
}

variable "connecting_role" {
  description = <<-EOT
    The role the root's postgresql provider connects as — its `username`. A
    NAME, not a credential. REQUIRED, no default: on PostgreSQL 16+ a
    non-superuser CREATEROLE identity cannot act as a role it created until it
    is granted that role, and this module grants each managed role to exactly
    this one (main.tf § postgresql_grant_role.connecting_role). The provider
    exposes no way to read the connected user back, so the root states it.
  EOT
  type        = string

  validation {
    condition     = length(trimspace(var.connecting_role)) > 0
    error_message = "connecting_role must name the role the postgresql provider connects as."
  }
}

variable "roles" {
  description = <<-EOT
    The login roles to ensure, by full name. Each gets a generated 32-character
    password, exposed through the `role_passwords` output for the consumer to
    route into its own secret store. REQUIRED, no default.

    Passwords are GENERATED rather than accepted: a password supplied as an
    input is a password that has been written somewhere before it reaches state.
  EOT
  type        = set(string)

  validation {
    condition     = alltrue([for name in var.roles : can(regex("^[a-z_][a-z0-9_]{0,62}$", name))])
    error_message = "Each role name must be lowercase alphanumerics and underscores, starting with a letter or underscore (1-63 chars)."
  }
}

variable "role_options" {
  description = "Optional per-role settings keyed by role name: create_database (CREATEDB), connection_limit (-1 = unlimited). A role absent from this map gets the defaults."
  type = map(object({
    create_database  = optional(bool, false)
    connection_limit = optional(number, -1)
  }))
  default = {}
}

variable "connect_grants" {
  description = <<-EOT
    Which roles may reach which databases, as `role => set(database)`. A role
    absent from the map reaches nothing — stated rather than defaulted, because
    "every role may reach every database" is exactly the posture the PUBLIC
    revoke ends.

    A role that OWNS the database it is granted gets `CONNECT, TEMPORARY,
    CREATE`; any other role gets `CONNECT`. That is not a convenience: this
    provider's grant is DECLARATIVE, so granting an owner CONNECT alone REVOKES
    its CREATE and TEMPORARY, and an owner that cannot CREATE on its own
    database cannot run a migration.
  EOT
  type        = map(set(string))
  default     = {}
}

variable "database_owners" {
  description = <<-EOT
    The role that OWNS each database, as `database => role`. A database absent
    from the map is left with whatever owner it has (the connecting admin, for
    one this module creates) — say who owns it when the application connects as
    a role that must run migrations. An owner is granted CREATE and USAGE on the
    database's `public` schema.
  EOT
  type        = map(string)
  default     = {}
}

variable "extensions" {
  description = <<-EOT
    The PostgreSQL extensions each database must carry, as
    `database => set(extension)`.

    THIS IS THE CREATE EXTENSION STEP, AND IT IS WHY THIS MODULE EXISTS. A
    trusted extension (`pg_trgm`, `pgcrypto`) can be created by a database
    owner, so an application's own migration can do it; `vector` is NOT trusted
    on a stock server, so it needs an identity the application does not have and
    must not be given. Declared here, it is created by the credential that
    already administers the server — the one the consumer configured the
    provider with — instead of by somebody with a shell on the box.

    A server that refuses (the extension is not installed on it, or not
    allow-listed by the cloud's own parameter) FAILS THE APPLY, loudly, naming
    the extension. That is the correct outcome and the reason this is not
    wrapped in a try: an application that boots against a database missing its
    extension fails later, further away, as a migration that cannot run.
  EOT
  type        = map(set(string))
  default     = {}

  validation {
    condition = alltrue([
      for _, names in var.extensions : alltrue([
        for name in names : can(regex("^[a-z_][a-z0-9_]{0,62}$", name))
      ])
    ])
    error_message = "Each extension name must be lowercase alphanumerics and underscores (the unquoted-identifier grammar)."
  }
}

variable "revoke_public_connect" {
  description = <<-EOT
    Revoke CONNECT from PUBLIC on every managed database. Default TRUE: a
    database every role on the server can reach is not a tenancy boundary, and
    on a shared server — which is the case this module is for — that is the
    difference between a deployment and a neighbour's data.
  EOT
  type        = bool
  default     = true
}

variable "role_ownership" {
  description = <<-EOT
    Whose roles these are. A closed set:

    - "installation" (default): the roles belong to one Xema installation.
      `ownership_marker`, `sql_connection` and `connecting_password` are
      required, and every role is stamped with the marker.
    - "unowned": the roles belong to no installation (a shared server's tenant
      that is not a Xema deployment, such as a shared Temporal server's role).
      `ownership_marker` must be null (mutually exclusive), no role is stamped,
      no `psql` is needed, and `sql_connection` / `connecting_password` are not
      required. The roles stay unmarked, so UNOWNED ROLES ARE NEVER ADOPTED BY
      ANY INSTALLATION: `xema installation import` always refuses them as
      foreign. That is the intended safety, not a gap.

    This is an explicit opt-out, never a fallback: a missing marker under
    "installation" is refused, and no placeholder marker can stand in for it.
  EOT
  type        = string
  default     = "installation"

  validation {
    condition     = contains(["installation", "unowned"], var.role_ownership)
    error_message = "role_ownership must be \"installation\" or \"unowned\"."
  }
}

variable "ownership_marker" {
  description = <<-EOT
    The text stamped on every role this module creates, as
    `COMMENT ON ROLE <role> IS '<ownership_marker>'`. REQUIRED when
    role_ownership = "installation" (no default; null is refused by the
    precondition on terraform_data.ownership_contract), and MUST be null when
    role_ownership = "unowned".

    It is the ownership marker of the Xema installation these roles belong to,
    `xema-deploy:managed deployment=<installation>`. An installer that later
    takes custody of the roles (`xema installation import`) reads it to decide
    that a role is its own rather than a neighbour's: a role without it is
    refused as foreign. The text is the kernel's grammar, so the caller passes
    it in (the deployment engine emits it) and this module never builds it.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.ownership_marker == null ? true : can(regex("^xema-deploy:managed deployment=[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.ownership_marker))
    error_message = "ownership_marker must be `xema-deploy:managed deployment=<installation>` with a lowercase deployment id (letters, digits, hyphens) — the marker the deployment engine emits. It is required: a role created without it is refused as foreign by `xema installation import`."
  }
}

variable "sql_connection" {
  description = <<-EOT
    Where the ownership marker is written from: the same server, as the same
    role, that the root's postgresql provider connects to. A NAME and an
    address, not a credential. REQUIRED when role_ownership = "installation";
    unused (may be null) when "unowned".

    The postgresql provider has no resource that comments on a role, so the
    marker is written by `psql` (which must be on the PATH of the host running
    the apply), connecting as `connecting_role` with `connecting_password`.
  EOT
  type = object({
    host     = string
    port     = optional(number, 5432)
    database = optional(string, "postgres")
    sslmode  = optional(string, "require")
  })
  default = null

  validation {
    condition     = var.sql_connection == null ? true : length(trimspace(var.sql_connection.host)) > 0
    error_message = "sql_connection.host must name the server the postgresql provider connects to."
  }
}

variable "connecting_password" {
  description = <<-EOT
    The password of `connecting_role` — the one the root already configures its
    postgresql provider with. A credential: it reaches `psql` only through the
    PGPASSWORD environment variable of the marker step, never its command line,
    and it is not kept in state. REQUIRED when role_ownership = "installation";
    unused (may be null) when "unowned".
  EOT
  type        = string
  sensitive   = true
  default     = null
}
