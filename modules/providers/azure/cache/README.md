# `providers/azure/cache`

Azure implementation of the [`cache` contract](../../../../docs/CONTRACTS.md#cache-optional).
An Azure Cache for Redis instance (`azurerm_redis_cache`) — TLS only, minimum
TLS 1.2. Optional: the platform's default topology runs valkey **in-cluster** via
Helm; reach for this only when a deployment wants the managed offering.

## Usage

```hcl
module "cache" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/cache?ref=v0.11.0"

  name     = "acme-dev-redis"
  region   = "westeurope"
  sku      = "Standard"
  capacity = 1
}
```

## Notes

- `sku` is a closed set (`Basic | Standard | Premium`); the family (`C`/`P`) is
  derived from it and `capacity` is the size step within it. A Premium cache
  below P1 is refused by a precondition.
- The non-TLS port is never enabled; `port` is the TLS port (6380). Clients
  connect with `rediss://`.
- Private-endpoint reachability is not modelled here (`public_network_access_enabled`
  is the only knob).
- The provider (`hashicorp/azurerm`) is configured by the **root/stack**, not
  here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `name`, `region` | yes | cache identity + location |
| `sku`, `capacity`, `redis_version` | no | `Basic` (default) / `Standard` / `Premium`; size step; engine major |
| `public_network_access_enabled` | no | reachability |
| `resource_group_name`, `tags` | no | use an existing resource group (else `"<name>-rg"`), tagging |

Outputs: `host`, `port`, `primary_key` (sensitive), `cache_id`,
`resource_group_name`.
