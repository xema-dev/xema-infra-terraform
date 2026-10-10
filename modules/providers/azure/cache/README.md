# providers/azure/cache

Azure Cache for Redis (`azurerm_redis_cache`), TLS only, minimum TLS 1.2.

## When to use it

Optional. Use it when a deployment wants a managed Redis instead of the in-cluster one. Implements the [`cache` contract](../../../../docs/CONTRACTS.md#cache-optional).

## Usage

```hcl
module "cache" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/cache?ref=v0.13.0"

  name     = "acme-dev-redis"
  region   = "westeurope"
  sku      = "Standard"
  capacity = 1
}
```

`sku` is `Basic`, `Standard` or `Premium` (Premium below P1 is refused). The non-TLS port is never enabled; clients connect to `port` (6380) with `rediss://`. The `azurerm` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Cache name (1-63 chars, letters/digits/hyphens; globally unique as <name>.redis.cache.windows.net). |
| `region` | yes | Azure location (e.g, "westeurope"). |
| `sku` | no | Azure Cache for Redis SKU: one of "Basic", "Standard", "Premium". |
| `capacity` | no | Size step within the SKU: 0-6 for Basic/Standard (C0-C6), 1-5 for Premium (P1-P5). |
| `redis_version` | no | Redis major version offered by Azure ("6"). |
| `public_network_access_enabled` | no | Whether the cache accepts traffic from the public internet (TLS + access key). |
| `resource_group_name` | no | Existing resource group to create the cache in. |
| `tags` | no | Tags applied to every created resource. |

Outputs: `host`, `port`, `primary_key`, `cache_id`, `resource_group_name`, `id`.
