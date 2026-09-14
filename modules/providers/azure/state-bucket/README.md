# `providers/azure/state-bucket`

Azure implementation of the [`state-bucket` contract](../../../../docs/CONTRACTS.md#state-bucket-bootstrap-only).
A storage account plus one private container dedicated to holding **Terraform
state** — versioning and soft delete forced on. Kept separate from
[`object-bucket`](../object-bucket/README.md) because its lifecycle and access
policy differ (it holds state, so it must be private + versioned).

## Usage

```hcl
module "state_bucket" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/state-bucket?ref=v0.1.0"

  name   = "acmedevtfstate"
  region = "westeurope"
}

output "backend_config_hint" {
  value = module.state_bucket.backend_config_hint
}
```

## Bootstrap (the chicken-and-egg)

A backend cannot reference an account that does not exist yet, so this account
is created **before** any root uses it as a backend:

1. **Create the account with LOCAL state** (or out-of-band): a tiny bootstrap
   root consuming just this module, with **no** `backend {}` block.
   `terraform apply` writes its own state to disk.
2. **Read `backend_config_hint`** to get the exact `backend "azurerm" {}` block.
3. **Point other roots at it**: drop that block (with a per-root `key`) into the
   substrate root's `backend.hcl` and `terraform init -migrate-state`.

The bootstrap root's own local state is small and rarely changes; commit nothing
sensitive from it (see [CONVENTIONS.md § State & secrets](../../../../docs/CONVENTIONS.md)).

## Notes

- The `azurerm` backend locks natively with **blob leases** — no lock table.
- Authenticate the backend with **Entra ID** (`use_azuread_auth = true`); the
  running principal needs *Storage Blob Data Contributor* on the container. No
  account key is ever committed or needed.
- Private access, versioning and soft delete are **not** configurable here: a
  state store that is public or unversioned is a footgun.
- The provider (`hashicorp/azurerm`) is configured by the **root/stack**, not
  here.

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | globally-unique storage account name (3-24 lowercase alphanumerics) |
| `region` | yes | Azure location |
| `container_name` | no | state container (default `tfstate`) |
| `replication` | no | `LRS` (default), `ZRS`, `GRS`, `GZRS` |
| `soft_delete_retention_days` | no | recovery window for deleted state blobs (default 30) |
| `resource_group_name`, `tags` | no | use an existing resource group (else `"<name>-rg"`), tagging |

Outputs: `bucket`, `endpoint`, `container`, `resource_group_name`,
`backend_config_hint` (the `backend "azurerm" {}` block).
