# postgres-tenancy

Creates databases, login roles, grants and extensions inside a PostgreSQL server this module does not own, over SQL, using the `postgresql` provider.

## When to use it

Use it when the server already exists and has no cloud control plane to reach (a host's Postgres, a server another team owns, a shared cluster). For a server Terraform creates, use `providers/<cloud>/managed-postgres`. The module manages nothing about the server itself (firewall, parameters, backups, sizing).

## Usage

```hcl
provider "postgresql" {
  host     = "db.internal.example"
  port     = 5432
  username = var.pg_admin_user
  password = var.pg_admin_password
  sslmode  = "require"
}

module "tenancy" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/postgres-tenancy?ref=v1.0.0"

  connecting_role     = var.pg_admin_user
  connecting_password = var.pg_admin_password
  sql_connection      = { host = "db.internal.example" }
  ownership_marker    = var.ownership_marker # "xema-deploy:managed deployment=acme-prod", from the deployment engine
  databases           = ["acme_app"]
  roles           = ["acme_app"]
  database_owners = { acme_app = "acme_app" }
  connect_grants  = { acme_app = ["acme_app"] }
  extensions      = { acme_app = ["vector"] }
}
```

Role passwords are generated. Read them with `terraform output -json role_passwords` and put them in your secret store.

- A role in `connect_grants` for a database it owns gets `CONNECT, TEMPORARY, CREATE`; any other role gets `CONNECT`.
- A role in `database_owners` gets `CREATE, USAGE` on that database's `public` schema, whoever owns the schema (`azure_pg_admin` on Azure Flexible Server). `connecting_role` must be a member of the schema's owner, or the apply fails with 42501.
- On PostgreSQL 16 and later the module grants every managed role to `connecting_role`. A role that already exists and was created by a different role needs `GRANT <role> TO <connecting_role> WITH ADMIN OPTION;` from its creator before import. The provider floor is `>= 1.24`.
- An extension the server refuses (not installed, or not allow-listed such as `azure.extensions`) fails the apply, naming it. Removing a name from `extensions` does not drop it.
- Every role gets `COMMENT ON ROLE <role> IS '<ownership_marker>'`, so `xema installation import` recognises it as the installation's own; an unmarked role is refused as foreign. The provider cannot set a comment, so `psql` writes it: `psql` must be on the PATH of the host running the apply, and it connects to `sql_connection` as `connecting_role`, with `connecting_password` passed as `PGPASSWORD` (never on a command line, never in state). The step re-runs when the role or the marker changes; a comment changed by hand afterwards is not detected.
- `role_ownership = "unowned"` (closed set: `"installation"` default, `"unowned"`) is the explicit opt-out for a tenant that belongs to no Xema installation: `ownership_marker` must be null (refused if set), no role is stamped, no `psql` is needed, and `sql_connection` / `connecting_password` may be null. Unowned roles are never adopted by any installation: `xema installation import` always refuses them as foreign. Under `"installation"` the marker, `sql_connection` and `connecting_password` are required (a precondition names them).
- Every object is importable. An import does not read back a role password, so the first apply after one rotates it.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `databases` | yes | The databases to ensure, by full name. |
| `connecting_role` | yes | The role the root's postgresql provider connects as — its `username`. |
| `roles` | yes | The login roles to ensure, by full name. |
| `role_options` | no | Optional per-role settings keyed by role name: create_database (CREATEDB), connection_limit (-1 = unlimited). |
| `connect_grants` | no | Which roles may reach which databases, as `role => set(database)`. |
| `database_owners` | no | The role that OWNS each database, as `database => role`. |
| `extensions` | no | The PostgreSQL extensions each database must carry, as `database => set(extension)`. |
| `role_ownership` | no | `"installation"` (default) or `"unowned"`; see above. |
| `ownership_marker` | with `"installation"` | `xema-deploy:managed deployment=<installation>`, written as every role's comment. Supplied by the deployment engine, never built here. |
| `sql_connection` | with `"installation"` | `{ host, port = 5432, database = "postgres", sslmode = "require" }`: where `psql` writes the marker — the server the provider connects to. |
| `connecting_password` | with `"installation"` | `connecting_role`'s password (sensitive), for the `psql` marker step only. |
| `revoke_public_connect` | no | Revoke CONNECT from PUBLIC on every managed database. |

Outputs: `databases`, `roles`, `role_passwords`, `role_ownership_markers`, `extensions`.
