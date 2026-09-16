# `providers/digitalocean/managed-postgres`

DigitalOcean implementation of the [`managed-postgres` contract](../../../../docs/CONTRACTS.md#managed-postgres).
Provisions a DO managed Postgres cluster (`engine = "pg"`) plus any number of
logical databases and roles.

## Usage

```hcl
module "postgres" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/managed-postgres?ref=v0.1.0"

  name           = "do-fra1-xema-pg"
  region         = "fra1"
  engine_version = "16"
  size           = "db-s-1vcpu-2gb"
  node_count     = 1
  vpc_id         = "00000000-0000-0000-0000-000000000000"

  databases = ["xema_core", "xema_biomes"]
  roles     = ["xema_app"]

  tags = { deployment = "acme-prod" }
}
```

## Notes

- **CA certificate caveat.** The `digitalocean_database_cluster` resource exposes
  **no** CA attribute, so the `ca_certificate` output is always `""`. The DO
  managed-Postgres CA is fetched **out-of-band**:

  ```sh
  doctl databases connection <cluster-id> --format SSL
  # or download the per-cluster CA from the DO control panel / API
  ```

  Wire that CA into your client (`sslmode=verify-full`) from the operator's
  private config, not from this module.
- `host`/`uri` prefer the **private** networking values (`private_host` /
  `private_uri`) and fall back to the public ones when private networking is not
  attached.
- `vpc_id` is passed through as `private_network_uuid`; empty string lets DO place
  the cluster in the region default VPC.
- Tags are rendered to DO's flat tag list as `"key:value"`, matching the
  [`cluster`](../cluster/README.md) module.
- The provider (`digitalocean/digitalocean`) is configured by the **root/stack**,
  not here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `name`, `region`, `engine_version`, `size` | yes | cluster identity + version + SKU |
| `node_count` | no | replica count (default `1`) |
| `vpc_id` | no | attach to an existing VPC (else region default) |
| `databases`, `roles` | no | logical databases / users to ensure exist |
| `tags` | no | tagging (rendered to DO's flat tag list) |

Outputs: `cluster_id`, `host`, `port`, `uri` (sensitive),
`ca_certificate` (sensitive, always `""` — see note).
