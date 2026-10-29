# providers/azure/object-bucket

An Azure storage account (StorageV2, TLS 1.2+, HTTPS only) for application blob storage, with optional pre-created containers. Implements the [`object-bucket` contract](../../../../docs/CONTRACTS.md#object-bucket). For Terraform state use [`state-bucket`](../state-bucket).

## When to use it

Use it for application blobs. The contract's bucket is the storage account, and `endpoint` is its primary Blob endpoint. Containers are optional: pre-create them only if the runtime identity cannot.

## Usage

```hcl
module "bucket" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/object-bucket?ref=v0.13.0"

  name        = "acmedevblob"
  region      = "westeurope"
  versioning  = true
  replication = "ZRS"
  containers  = ["acme-dev-uploads"]
}
```

`name` is 3-24 lowercase alphanumerics and globally unique. `acl` is `private` (default) or `public-read`. `replication` is `LRS`, `ZRS`, `GRS` or `GZRS`. Shared-key auth is on by default. The `azurerm` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Storage account name: 3-24 lowercase letters/digits, globally unique across Azure. |
| `region` | yes | Azure location (e.g, "westeurope"). |
| `acl` | no | Canned ACL: "private" (containers private, no anonymous access) or "public-read" (containers readable a... |
| `versioning` | no | Enable blob versioning on the account. |
| `containers` | no | Blob containers to pre-create. |
| `replication` | no | Storage redundancy: one of "LRS", "ZRS", "GRS", "GZRS". |
| `network_rules` | no | Opt-in VNet service-endpoint access, `{ virtual_network_subnet_ids }`; null (default) sets no rules. When set: `default_action = Deny`, `bypass = ["None"]`, only those subnets. Needs `public_network_access_enabled = true` and the `Microsoft.Storage` service endpoint on each subnet (not managed here). |
| `public_network_access_enabled` | no | Whether the account's endpoints accept traffic from the public internet (authenticated; anonymous access is... |
| `shared_access_key_enabled` | no | Allow account-key (shared key) authentication — what the platform's blob-storage adapter uses today. |
| `resource_group_name` | no | Existing resource group to create the account in. |
| `tags` | no | Tags applied to every created resource. |

Outputs: `bucket`, `endpoint`, `account_name`, `account_id`, `primary_blob_endpoint`, `primary_access_key`, `container_names`, `resource_group_name`.
