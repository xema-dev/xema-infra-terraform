# `providers/digitalocean/object-bucket`

DigitalOcean implementation of the [`object-bucket` contract](../../../../docs/CONTRACTS.md#object-bucket).
A single DO Spaces bucket (`digitalocean_spaces_bucket`) for application/biome
object storage — **not** for Terraform state (use
[`state-bucket`](../state-bucket/README.md) for that).

## Usage

```hcl
module "bucket" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/object-bucket?ref=v0.1.0"

  name       = "xema-prod-artifacts"
  region     = "fra1"
  acl        = "private"
  versioning = true
}
```

## Notes

- `acl` is a closed set validated to `private` | `public-read`.
- `region` is intentionally **not** validated against a fixed list so new DO
  Spaces regions work without a module change. Supported at time of writing:
  `nyc3`, `ams3`, `sgp1`, `sfo2`, `sfo3`, `fra1`, `syd1`, `blr1`.
- `endpoint` is derived as `https://<region>.digitaloceanspaces.com` (the
  S3-compatible endpoint); the bucket is then addressed as a path or
  virtual-hosted prefix per your client.
- The provider (`digitalocean/digitalocean`) is configured by the **root/stack**,
  not here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | globally-unique bucket name |
| `region` | yes | Spaces region slug |
| `acl` | no | `private` (default) or `public-read` |
| `versioning` | no | enable object versioning (default `false`) |

Outputs: `bucket`, `endpoint`.
