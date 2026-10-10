# providers/digitalocean/dns

A DigitalOcean DNS zone (`digitalocean_domain`) and its records. Implements the [`dns` contract](../../../../docs/CONTRACTS.md#dns).

## Usage

```hcl
module "dns" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/dns?ref=v0.13.0"

  domain = "example.com"

  records = {
    apex = { name = "@", type = "A", value = "203.0.113.10" }
    www  = { name = "www", type = "CNAME", value = "example.com." }
  }
}
```

A CNAME value must be a fully qualified name with a trailing dot; the module does not add it. `record_ids` maps each input key to the record id. The `digitalocean` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `domain` | yes | Managed zone apex (e.g, "example.com"). |
| `records` | no | DNS records keyed by a stable id. |

Outputs: `domain`, `record_ids`.
