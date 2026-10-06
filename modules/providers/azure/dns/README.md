# `providers/azure/dns`

Azure implementation of the [`dns` contract](../../../../docs/CONTRACTS.md#dns).
Manages an Azure DNS zone (`azurerm_dns_zone`) and its records — one Azure
resource type per record type (`A`, `AAAA`, `CNAME`, `TXT`). Optionally mints the
workload identity cert-manager's ACME DNS-01 solver uses to edit the zone.

## Usage

```hcl
module "dns" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/dns?ref=v0.13.0"

  domain = "example.com"
  region = "westeurope" # only for the resource group / identity; the zone is global

  records = {
    apex     = { name = "@", type = "A", value = "203.0.113.10" }
    wildcard = { name = "*", type = "A", value = "203.0.113.10" }
    www      = { name = "www", type = "CNAME", value = "example.com" }
    spf      = { name = "@", type = "TXT", value = "v=spf1 -all" }
  }

  dns01_workload_identity = {
    enabled         = true
    oidc_issuer_url = module.cluster.oidc_issuer_url
  }
}
```

## Notes

- **Record types are a closed set** — `A | AAAA | CNAME | TXT` — validated at
  the variable, because each maps to a distinct Azure resource. Wildcards (`*`,
  `*.sub`) and the apex (`@`) are ordinary names.
- `name_servers` is the delegation set: point the apex at these at your
  registrar, or the zone answers nothing.
- `region` is needed only for the two resources that need a location — the
  created resource group and the DNS-01 identity; the zone is global. Each of
  those fails fast with a precondition naming the missing input.
- `dns01_workload_identity` creates a user-assigned identity holding **DNS Zone
  Contributor on this zone only**, federated (`api://AzureADTokenExchange`) to
  `system:serviceaccount:<ns>:<sa>` through the cluster's OIDC issuer. Feed
  `dns01_client_id`, `subscription_id` and `resource_group_name` to the
  [`gateway-tls`](../../../cluster-addons/gateway-tls/README.md) addon's
  `dns01-azure` solver.
- The provider (`hashicorp/azurerm`) is configured by the **root/stack**, not
  here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `domain` | yes | managed zone apex |
| `records` | no | records keyed by a stable id (name, type, value, ttl) |
| `region` | conditionally | location for the created resource group / DNS-01 identity |
| `resource_group_name` | no | use an existing resource group (else `"<domain-with-hyphens>-dns-rg"`) |
| `dns01_workload_identity` | no | mint the cert-manager DNS-01 identity |
| `tags` | no | tagging |

Outputs: `domain`, `record_ids` (map of input key → record id), `name_servers`,
`zone_id`, `resource_group_name`, `subscription_id`, `dns01_client_id`.
