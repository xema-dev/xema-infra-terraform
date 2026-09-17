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
    Which roles may CONNECT to which databases, as `role => set(database)`. A
    role absent from the map gets CONNECT to nothing beyond what it owns —
    stated rather than defaulted, because "every role may reach every database"
    is exactly the posture the PUBLIC revoke below exists to end.
  EOT
  type        = map(set(string))
  default     = {}
}

variable "database_owners" {
  description = <<-EOT
    The role that OWNS each database, as `database => role`. A database absent
    from the map is left with whatever owner it has (the connecting admin, for
    one this module creates) — say who owns it when the application connects as
    a role that must run migrations.
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
