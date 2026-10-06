# `providers/azure/object-bucket`

Azure implementation of the [`object-bucket` contract](../../../../docs/CONTRACTS.md#object-bucket).
A single **storage account** (`azurerm_storage_account`, StorageV2, TLS 1.2+,
HTTPS only) for application/biome blob storage, plus optional pre-created
containers — **not** for Terraform state (use
[`state-bucket`](../state-bucket/README.md) for that).

## Usage

```hcl
module "bucket" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/object-bucket?ref=v0.11.0"

  name        = "acmedevblob"
  region      = "westeurope"
  acl         = "private"
  versioning  = true
  replication = "ZRS"
  containers  = ["acme-dev-uploads"]
}
```

## Notes

- The contract's **bucket is the storage account**; `endpoint` is its primary
  **Blob** endpoint, not an S3 URL. The platform's `@xemahq/blob-storage` Azure
  adapter addresses containers under it as `<prefix>-<logical>` and **creates
  them at boot**, so `containers` is optional — pre-create only when the
  runtime identity may not.
- `acl` is a closed set: `private` (default) or `public-read`, which sets
  `allow_nested_items_to_be_public` on the account and `container_access_type =
  "blob"` on every pre-created container.
- `replication` is a closed set (`LRS | ZRS | GRS | GZRS`); `name` is validated
  to Azure's 3-24 lowercase alphanumerics and must be globally unique.
- Shared-key auth stays on by default because the platform adapter uses an
  account key today; flip `shared_access_key_enabled` off once consumers
  authenticate with Entra identities.
- The provider (`hashicorp/azurerm`) is configured by the **root/stack**, not
  here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | storage account name (3-24 lowercase alphanumerics, globally unique) |
| `region` | yes | Azure location |
| `acl` | no | `private` (default) or `public-read` |
| `versioning` | no | blob versioning (default `false`) |
| `containers` | no | containers to pre-create (default none) |
| `replication` | no | `LRS` (default), `ZRS`, `GRS`, `GZRS` |
| `public_network_access_enabled`, `shared_access_key_enabled` | no | reachability + auth mode |
| `resource_group_name`, `tags` | no | use an existing resource group (else `"<name>-rg"`), tagging |

Outputs: `bucket`, `endpoint`, `account_name`, `account_id`,
`primary_blob_endpoint`, `primary_access_key` (sensitive), `container_names`,
`resource_group_name`.
