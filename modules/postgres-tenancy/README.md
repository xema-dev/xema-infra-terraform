# `postgres-tenancy`

Cloud-agnostic [`postgres-tenancy`](../../docs/CONTRACTS.md#cloud-agnostic-modules-no-per-cloud-implementation-needed)
module. Databases, login roles, grants and **extensions** inside a PostgreSQL
server this module does not own.

## Why it exists

`providers/<cloud>/managed-postgres` creates a server and does its tenancy
through the cloud's control plane. A server the consumer ALREADY has — a box's
Postgres, a Flexible Server another team's Terraform owns, a cluster shared with
other products — has no control plane to reach, so its tenancy is done inside
the server over SQL.

That is the case this fleet is mostly in, and it is the case that had no module.
The databases were created by a generated SQL file somebody ran by hand behind a
superuser door, and `CREATE EXTENSION vector` — which a database owner cannot
run, because `vector` is not a trusted extension — was run with a shell on the
host. Until it was, every service whose migrations need it crashlooped on
`permission denied to create extension "vector"`.

## Usage

```hcl
provider "postgresql" {
  host     = "db.internal.example" # the server the CONSUMER owns
  port     = 5432
  username = var.pg_admin_user     # an identity that may create roles and extensions
  password = var.pg_admin_password
  database = "postgres"
  sslmode  = "require"
}

module "tenancy" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/postgres-tenancy?ref=v1.0.0"

  connecting_role = var.pg_admin_user # the provider's username — see below

  # EXAMPLE roster — yours is derived from what you deploy.
  databases = ["acme_biomes", "acme_openfga", "acme_mcp_gateway"]
  roles     = ["acme_app"]

  database_owners = { for db in ["acme_biomes", "acme_openfga", "acme_mcp_gateway"] : db => "acme_app" }
  connect_grants  = { acme_app = ["acme_biomes", "acme_openfga", "acme_mcp_gateway"] }

  # The step that used to need a shell on the box.
  extensions = { acme_biomes = ["vector", "pg_trgm"] }
}
```

The role passwords are generated, never supplied: a password given as an input
has been written somewhere before it reaches state. Read them out once and route
them into the secret store the deployment reads —
`tofu output -json role_passwords` (or `terraform`).

## The owner keeps owner privileges

A role listed in `connect_grants` for a database it OWNS is granted `CONNECT,
TEMPORARY, CREATE`; any other role is granted `CONNECT`.

This provider's `postgresql_grant` is **declarative** — it sets exactly the
privileges listed and revokes the rest — so granting an owner `CONNECT` alone
takes CREATE and TEMPORARY away from it, and an owner that cannot CREATE on its
own database cannot create a schema or a table. Measured against PostgreSQL
18.6, against the hand-run bootstrap SQL this module replaces: the SQL leaves
`<role>=CTc/<role>`, and the CONNECT-only form left `<role>=c/<role>`.

## PostgreSQL 16+: the connecting role is granted every managed role

The module is meant to run as a NON-superuser holding CREATEROLE (the Azure
Flexible Server admin, and what any shared server should hand out). From
PostgreSQL 16 such a role gets, for every role it creates, only an ADMIN OPTION
membership with SET and INHERIT both false (`createrole_self_grant` is `''` by
default): it may grant the role, it may not act as it. Measured against
`postgres:16` with a `CREATEROLE CREATEDB` login:

| provider | without the grant |
| --- | --- |
| 1.22, 1.23 | apply fails: `Error creating database "…": pq: must be able to SET ROLE "<owner>"` |
| 1.24 – 1.27 | apply is GREEN, but every database grant is a silent no-op: PUBLIC keeps `Tc`, the non-owner role never gets CONNECT, and every later plan shows the same in-place drift |

So the module issues `GRANT <role> TO <connecting_role>` for every role in
`roles` (`postgresql_grant_role`, `with_admin_option = false`) before any
database names an owner. With it, the grants land
(`{<owner>=CTc/<owner>,<other>=c/<owner>}`, no PUBLIC entry), a second plan is
empty, and destroy is clean (measured on provider 1.24.0 and 1.27.0). The
provider floor is `>= 1.24`: 1.22, even with the grant, cannot drop a role it
created on 16 (`permission denied to reassign objects`).

Not covered, by construction: a role that ALREADY exists and was created by a
different role (a superuser running a bootstrap file) gives the connecting role
no ADMIN OPTION on it, so it can neither alter nor grant it — the apply stops
on `permission denied to alter role` (measured, on 16 with provider 1.27.0).
Adopting such a role needs its creator to run, once:

```sql
GRANT <role> TO <connecting_role> WITH ADMIN OPTION;
```

This is NOT detected before the apply, and cannot be with this provider: its
only data sources are `postgresql_schemas`, `postgresql_sequences` and
`postgresql_tables` (1.27.0 schema), none of which reads `pg_auth_members` or
any other catalog row, and no provider is added just to ask. Check by hand
before importing such a role:
`SELECT admin_option FROM pg_auth_members WHERE roleid = '<role>'::regrole AND member = '<connecting_role>'::regrole;`
— no row, or `f`, means the grant above is needed first.

## Extensions, and why a failure here is the point

A trusted extension (`pg_trgm`, `pgcrypto`) can be created by a database owner,
so an application's own migration can do it. `vector` cannot: it needs an
identity the application does not have and must not be given.

A server that refuses — the extension is not installed on it, or a cloud has not
allow-listed it in its own parameter (`azure.extensions` on Azure Flexible
Server) — **fails the apply, naming the extension**. That is the correct
outcome: the alternative is an application booting against a database missing
its extension and failing later, further away, as a migration that cannot run.

Removing a name from `extensions` does NOT drop the extension
(`drop_cascade = false`): a drop takes the indexes and column types that depend
on it. The removal shows as drift, and a deliberate drop is an explicit operator
action against the server.

## Adopting a server that already carries its tenancy

Every object is importable, which is how a fleet whose databases were created by
a hand-run SQL file moves under Terraform without recreating anything:

```
tofu import 'module.tenancy.postgresql_database.this["acme_biomes"]' acme_biomes
tofu import 'module.tenancy.postgresql_role.this["acme_app"]'        acme_app
```

Encoding, collation and template are ignored after create for the same reason: a
module that pinned them would refuse to adopt any existing database whose locale
differs, and adoption is most of what this module is for. A role's password is
NOT read back by an import — the first apply after one sets the generated value,
which is a rotation, so schedule it like one.

| Input | Required | Description |
| --- | --- | --- |
| `databases` | **yes** | the databases to ensure (unquoted-identifier grammar) |
| `existing_databases` | no | databases a control plane already created; granted on (PUBLIC revoke, `connect_grants`, `extensions`) but never created, altered or dropped |
| `connecting_role` | **yes** | the role the provider connects as; granted every role in `roles` (PostgreSQL 16+) |
| `roles` | **yes** | the login roles to ensure; each gets a generated password |
| `role_options` | no | per-role `create_database` / `connection_limit` |
| `database_owners` | no | `database => role`; who owns it, hence who can migrate it |
| `connect_grants` | no | `role => set(database)`; stated, never defaulted. An owner gets `CONNECT, TEMPORARY, CREATE`; anyone else `CONNECT` |
| `extensions` | no | `database => set(extension)` |
| `revoke_public_connect` | no | default `true` — a database PUBLIC can reach is not a boundary |

Outputs: `databases`, `roles`, `role_passwords` (sensitive), `extensions`.

## Notes

- The `postgresql` provider is configured by the **root**, not here (see
  [CONVENTIONS.md](../../docs/CONVENTIONS.md)). This module never learns a host,
  a port or an admin credential.
- It manages nothing ABOUT the server — no firewall, no parameter, no backup
  policy, no sizing. Those belong to whoever owns it.
- Every cross-input requirement is a precondition that fires before the first
  object is created, so a roster naming a database this module does not manage
  refuses whole rather than applying halfway.
