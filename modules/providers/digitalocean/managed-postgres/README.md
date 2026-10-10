# providers/digitalocean/managed-postgres

A DigitalOcean managed Postgres cluster with logical databases and roles. Implements the [`managed-postgres` contract](../../../../docs/CONTRACTS.md#managed-postgres).

## Usage

```hcl
module "postgres" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/managed-postgres?ref=v0.13.0"

  name           = "do-fra1-xema-pg"
  region         = "fra1"
  engine_version = "16"
  size           = "db-s-1vcpu-2gb"
  vpc_id         = "00000000-0000-0000-0000-000000000000"

  databases = ["app_core"]
  roles     = ["app"]
}
```

- `ca_certificate` is always `""` because the provider exposes none. Fetch the CA with `doctl databases connection <cluster-id> --format SSL` for `sslmode=verify-full`.
- `host` and `uri` use the private values when private networking is attached.
- The `digitalocean` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Database cluster name. |
| `region` | yes | DigitalOcean region slug (e.g, "fra1"). |
| `engine_version` | yes | Major Postgres version (e.g, "16"). |
| `size` | yes | DO managed-database size slug (e.g, "db-s-1vcpu-2gb"). |
| `node_count` | no | Node count (1 = single node, 2+ = primary plus standby replicas). |
| `vpc_id` | no | Existing VPC uuid to attach the cluster to for private networking. |
| `databases` | no | Logical databases to ensure exist on the cluster. |
| `roles` | no | Logical roles/users to ensure exist on the cluster. |
| `tags` | no | Tags applied to the cluster. |

Outputs: `cluster_id`, `host`, `port`, `uri`, `ca_certificate`.
