# providers/digitalocean/state-bucket

A private, versioned DigitalOcean Spaces bucket that holds Terraform state. Implements the [`state-bucket` contract](../../../../docs/CONTRACTS.md#state-bucket-bootstrap-only).

## When to use it

Use it once, to bootstrap the backend other roots store state in.

## Usage

```hcl
module "state_bucket" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/digitalocean/state-bucket?ref=v0.13.0"

  name   = "acme-prod-tfstate"
  region = "fra1"
}

output "backend_config_hint" {
  value = module.state_bucket.backend_config_hint
}
```

1. Apply a bootstrap root containing only this module, with no `backend {}` block.
2. Put the `backend_config_hint` block (an `s3` backend), with a per-root `key`, in each root's `backend.hcl` and run `terraform init -migrate-state`.

Spaces is S3-compatible, so the hint skips the AWS-specific validations. Supply the Spaces key as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from your environment. Privacy and versioning are not configurable.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Globally-unique Spaces bucket name dedicated to Terraform state. |
| `region` | yes | DO Spaces region slug. |

Outputs: `bucket`, `endpoint`, `backend_config_hint`.
