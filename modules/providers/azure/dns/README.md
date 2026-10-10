# providers/azure/dns

An Azure DNS zone (`azurerm_dns_zone`) and its records, with an optional workload identity for cert-manager's DNS-01 solver. Implements the [`dns` contract](../../../../docs/CONTRACTS.md#dns).

## When to use it

Use it to host a zone on Azure DNS and, optionally, to let cert-manager issue certificates by editing that zone.

## Usage

```hcl
module "dns" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/dns?ref=v0.13.0"

  domain = "example.com"
  region = "westeurope"

  records = {
    wildcard = { name = "*", type = "A", value = "203.0.113.10" }
    www      = { name = "www", type = "CNAME", value = "example.com" }
  }

  dns01_workload_identity = {
    enabled         = true
    oidc_issuer_url = module.cluster.oidc_issuer_url
  }
}
```

- Record types are `A`, `AAAA`, `CNAME` and `TXT`; the apex is `@`.
- Point the registrar's delegation at the `name_servers` output.
- `region` is needed only for the created resource group and the DNS-01 identity.
- The DNS-01 identity holds DNS Zone Contributor on this zone only. Pass `dns01_client_id`, `subscription_id` and `resource_group_name` to the [`gateway-tls`](../../../cluster-addons/gateway-tls) `dns01-azure` solver.
- The `azurerm` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `domain` | yes | Managed zone apex (e.g, "example.com"). |
| `records` | no | DNS records keyed by a stable id. |
| `region` | no | Azure location for the resources that need one — the created resource group (when resource_group_name is em... |
| `resource_group_name` | no | Existing resource group to create the zone in. |
| `dns01_workload_identity` | no | Optionally mint a user-assigned identity that may edit THIS zone (DNS Zone Contributor) and federate it to... |
| `tags` | no | Tags applied to every created resource. |

Outputs: `domain`, `record_ids`, `name_servers`, `zone_id`, `resource_group_name`, `subscription_id`, `dns01_client_id`, `assigned_role_names`.
