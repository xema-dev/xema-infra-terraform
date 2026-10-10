# providers/azure/state-bucket

A storage account and one private container that hold Terraform state, with versioning and soft delete forced on. Implements the [`state-bucket` contract](../../../../docs/CONTRACTS.md#state-bucket-bootstrap-only). Separate from [`object-bucket`](../object-bucket) because state must be private and versioned.

## When to use it

Use it once, to bootstrap the backend other roots store state in.

## Usage

```hcl
module "state_bucket" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/state-bucket?ref=v0.13.0"

  name   = "acmedevtfstate"
  region = "westeurope"
}

output "backend_config_hint" {
  value = module.state_bucket.backend_config_hint
}
```

1. Apply a bootstrap root containing only this module, with no `backend {}` block (state stays local).
2. Put the `backend_config_hint` block, with a per-root `key`, in each root's `backend.hcl` and run `terraform init -migrate-state`.

The `azurerm` backend locks with blob leases. Authenticate with Entra ID (`use_azuread_auth = true`); the principal needs Storage Blob Data Contributor on the container. Private access, versioning and soft delete are not configurable.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Storage account name dedicated to Terraform state: 3-24 lowercase letters/digits, globally unique across Az... |
| `region` | yes | Azure location (e.g, "westeurope"). |
| `container_name` | no | Blob container holding the state objects. |
| `replication` | no | Storage redundancy: one of "LRS", "ZRS", "GRS", "GZRS". |
| `soft_delete_retention_days` | no | Days a deleted state blob (or blob version) stays recoverable. |
| `shared_access_key_enabled` | no | Allow account-key access (default true). |
| `resource_group_name` | no | Existing resource group to create the account in. |
| `tags` | no | Tags applied to every created resource. |

Outputs: `bucket`, `endpoint`, `container`, `resource_group_name`, `backend_config_hint`.
