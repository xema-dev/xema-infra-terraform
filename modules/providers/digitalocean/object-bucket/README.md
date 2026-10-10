# providers/digitalocean/object-bucket

A DigitalOcean Spaces bucket for application object storage. Implements the [`object-bucket` contract](../../../../docs/CONTRACTS.md#object-bucket). For Terraform state use [`state-bucket`](../state-bucket).

## Usage

```hcl
module "bucket" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/object-bucket?ref=v0.13.0"

  name       = "acme-prod-artifacts"
  region     = "fra1"
  versioning = true
}
```

`acl` is `private` (default) or `public-read`. `endpoint` is `https://<region>.digitaloceanspaces.com`. `region` is not validated against a fixed list. The `digitalocean` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Globally-unique Spaces bucket name. |
| `region` | yes | DO Spaces region slug. |
| `acl` | no | Canned ACL: one of "private" or "public-read". |
| `versioning` | no | Enable object versioning on the bucket. |

Outputs: `bucket`, `endpoint`.
