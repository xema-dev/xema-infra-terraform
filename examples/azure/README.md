# Example: Azure substrate root

A runnable root that calls [`stacks/azure/xema-substrate`](../../stacks/azure/xema-substrate) with placeholder values. Copy it into your own private root and replace the placeholders.

## Files

| File | Purpose |
| --- | --- |
| `main.tf` | calls `module "substrate"`, declares the partial `azurerm` backend and the outputs |
| `variables.tf` | every input passed through to the stack |
| `terraform.tfvars.example` | greenfield placeholder values |
| `consume.tfvars.example` | consume-mode placeholders: cloud infrastructure disabled, existing cluster read by name |
| `backend.hcl.example` | Azure Storage backend configuration |

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars   # or consume.tfvars.example
cp backend.hcl.example      backend.hcl
# edit both, replacing every placeholder

az login && az account set --subscription <id>
export TF_VAR_key_vault_secrets='{"postgres-app-password":"..."}'
terraform init -backend-config=backend.hcl
```

The state account must already exist; bootstrap it with [`providers/azure/state-bucket`](../../modules/providers/azure/state-bucket).

- **Greenfield:** the `kubernetes`, `helm` and `postgresql` providers connect to resources the stack creates, so apply in phases. First `terraform apply -target=module.substrate.module.cluster -target=module.substrate.module.postgres -target=module.substrate.module.dns -target=module.substrate.module.blob -target=module.substrate.module.secrets_backend`, then `terraform apply`. After the Helm bring-up, set `enable_identity_realm = true` and apply again. The operator must reach the Postgres server (private access needs a VPN, bastion or runner in the VNet).
- **Consume:** with `enable_cluster = false` the cluster is read by name and one `terraform apply` is enough. Run it where `existing_postgres_host` resolves.
- **Existing infrastructure:** follow [`docs/import-runbook.md`](../../docs/import-runbook.md).

`platform_databases` and `workload_namespaces` have no default; the tfvars examples show one answer. See the [stack README](../../stacks/azure/xema-substrate/README.md) for derived names and the names you can override.
