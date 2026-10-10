# providers/azure/managed-postgres

An Azure Database for PostgreSQL Flexible Server. Databases, roles and grants are applied inside the server by [`postgres-tenancy`](../../../postgres-tenancy). Implements the [`managed-postgres` contract](../../../../docs/CONTRACTS.md#managed-postgres).

## When to use it

Use it to create the database server of the Azure substrate.

## Usage

```hcl
module "postgres" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/managed-postgres?ref=v0.13.0"

  name           = "acme-dev-pg"
  region         = "westeurope"
  engine_version = "16"
  size           = "B_Standard_B2s"

  network_access      = "private"
  vpc_id              = module.cluster.vpc_id
  delegated_subnet_id = module.cluster.delegated_subnet_id

  databases       = ["acme_dev_app"]
  database_owners = { acme_dev_app = "acme_dev" }
  roles           = ["acme_dev"]
}
```

- Roles and grants need the `postgresql` provider, configured by the root from the `host`, `administrator_login` and `administrator_password` outputs, with `superuser = false` and `sslmode = "require"`.
- A `private` server answers only inside the VNet, so `terraform apply` must run from inside it (a VPN, bastion or runner). `network_access = "public"` needs explicit `public_firewall_rules`.
- `node_count` is `1`, or `2` for zone-redundant HA.
- `ca_certificate` is always `""`: the chain is anchored on public roots.
- Passwords are generated and kept in state. Set `generate_administrator_password = false` to supply your own.
- The `azurerm` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Flexible Server name (3-63 chars, lowercase letters, digits, hyphens; globally unique as <name>.postgres.da... |
| `region` | yes | Azure location (e.g, "westeurope"). |
| `engine_version` | yes | Major Postgres version (e.g, "16"). |
| `size` | yes | Flexible Server SKU name (e.g, "B_Standard_B2s", "GP_Standard_D2ds_v5"). |
| `node_count` | no | 1 = single zone; 2 = zone-redundant high availability with one standby. |
| `vpc_id` | no | Virtual network id to link the private DNS zone to (the network the clients live in). |
| `network_access` | no | How the server is reached: "private" (VNet-injected via delegated_subnet_id + a private DNS zone; no publ... |
| `delegated_subnet_id` | no | Id of a subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers (providers/azure/cluster exposes one... |
| `private_dns_zone_name` | no | Name of the private DNS zone created for a private server. |
| `private_dns_zone_id` | no | Id of an EXISTING private DNS zone for a private server, owned outside this module (e.g, by an enterprise l... |
| `public_firewall_rules` | no | Firewall rules for a PUBLIC server, keyed by a stable id: { start_ip_address, end_ip_address }. |
| `storage_mb` | no | Provisioned storage in MB (Azure accepts fixed steps: 32768, 65536, 131072, …). |
| `auto_grow_enabled` | no | Let Azure grow storage automatically when it fills. |
| `backup_retention_days` | no | Backup retention in days (7-35). |
| `geo_redundant_backup_enabled` | no | Replicate backups to the paired region. |
| `zone` | no | Availability zone for the primary ("1", "2", "3"). |
| `administrator_login` | no | Server administrator login. |
| `generate_administrator_password` | no | Generate the administrator password with random_password (exposed as the sensitive administrator_password o... |
| `administrator_password` | no | Server administrator password, used when generate_administrator_password = false. |
| `databases` | no | Logical databases to ensure exist on the server. |
| `database_owners` | no | The role that OWNS each database, as `database => role` (both must be in `databases` / `roles`). |
| `roles` | no | Logical login roles to ensure exist on the server, created through the cyrilgdn/postgresql provider (module... |
| `role_options` | no | Optional per-role settings keyed by role name: create_database (CREATEDB), connection_limit (-1 = unlimited). |
| `extensions` | no | PostgreSQL extensions to allow-list on the server (the azure.extensions server parameter, which CREATE EXTE... |
| `resource_group_name` | no | Existing resource group to create the server in. |
| `tags` | no | Tags applied to every created resource. |

Outputs: `cluster_id`, `host`, `port`, `uri`, `ca_certificate`, `administrator_login`, `administrator_password`, `role_passwords`, `databases`, `resource_group_name`, `private_dns_zone_id`.
