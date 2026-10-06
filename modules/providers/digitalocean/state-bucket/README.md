# `providers/digitalocean/state-bucket`

DigitalOcean implementation of the [`state-bucket` contract](../../../../docs/CONTRACTS.md#state-bucket-bootstrap-only).
A DO Spaces bucket dedicated to holding **Terraform state** — always `private`,
versioning forced on. Kept separate from
[`object-bucket`](../object-bucket/README.md) because its lifecycle and access
policy differ (it holds state, so it must be private + versioned).

## Usage

```hcl
module "state_bucket" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/state-bucket?ref=v0.11.0"

  name   = "acme-prod-tfstate"
  region = "fra1"
}

output "backend_config_hint" {
  value = module.state_bucket.backend_config_hint
}
```

## Bootstrap (the chicken-and-egg)

A backend cannot reference a bucket that does not exist yet, so this bucket is
created **before** any root uses it as a backend:

1. **Create the bucket with LOCAL state** (or out-of-band): a tiny bootstrap root
   consuming just this module, with **no** `backend {}` block. `terraform apply`
   writes its own state to disk.
2. **Read `backend_config_hint`** to get the exact `backend "s3" {}` block.
3. **Point other roots at it**: drop that block (with a per-root `key`) into the
   substrate root's `backend.hcl` and `terraform init -migrate-state`.

The bootstrap root's own local state is small and rarely changes; commit nothing
sensitive from it (see [CONVENTIONS.md § State & secrets](../../../../docs/CONVENTIONS.md)).

## Notes

- DO Spaces is **S3-compatible**, so the backend is the `s3` backend with the
  AWS-specific validations skipped (`skip_credentials_validation`,
  `skip_metadata_api_check`, `skip_region_validation`) and a dummy
  `region = "us-east-1"` that Spaces ignores. `backend_config_hint` emits the
  full block.
- Credentials (DO Spaces access key / secret) are supplied **out-of-band** as
  `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — never committed.
- `acl = "private"` and `versioning.enabled = true` are **not** configurable here:
  a state bucket that is public or unversioned is a footgun.
- The provider (`digitalocean/digitalocean`) is configured by the **root/stack**,
  not here.

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | globally-unique state bucket name |
| `region` | yes | Spaces region slug |

Outputs: `bucket`, `endpoint`, `backend_config_hint` (the `backend "s3" {}` block).
