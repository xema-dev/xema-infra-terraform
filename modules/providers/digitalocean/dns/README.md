# `providers/digitalocean/dns`

DigitalOcean implementation of the [`dns` contract](../../../../docs/CONTRACTS.md#dns).
Manages a DO DNS zone (`digitalocean_domain`) and its records
(`digitalocean_record`).

## Usage

```hcl
module "dns" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/dns?ref=v0.12.0"

  domain = "example.com"

  records = {
    apex = {
      name  = "@"
      type  = "A"
      value = "203.0.113.10"
    }
    www = {
      name  = "www"
      type  = "CNAME"
      value = "example.com." # CNAME value MUST be an FQDN with a trailing dot
    }
    spf = {
      name  = "@"
      type  = "TXT"
      value = "v=spf1 -all"
    }
  }
}
```

## Notes

- **CNAME values must be FQDNs with a trailing dot** (e.g. `"target.example.com."`).
  DigitalOcean stores the value verbatim; this module does **not** mutate or
  append the dot, so the caller is responsible for supplying a fully-qualified
  value. A missing trailing dot makes DO treat the value as relative to the zone.
- `record_ids` maps each input `records` key to the provider record id, so callers
  can reference a specific record without depending on iteration order.
- The provider (`digitalocean/digitalocean`) is configured by the **root/stack**,
  not here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `domain` | yes | managed zone apex |
| `records` | no | records keyed by a stable id (name, type, value, ttl) |

Outputs: `domain`, `record_ids` (map of input key → record id).
