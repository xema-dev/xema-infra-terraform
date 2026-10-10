# Example: DigitalOcean substrate root

A runnable root that calls [`stacks/digitalocean/xema-substrate`](../../stacks/digitalocean/xema-substrate) with placeholder values. Copy it into your own private root and replace the placeholders.

## Files

| File | Purpose |
| --- | --- |
| `main.tf` | calls `module "substrate"`, declares the partial `s3` backend and the outputs |
| `variables.tf` | every input passed through to the stack |
| `terraform.tfvars.example` | greenfield placeholder values |
| `consume.tfvars.example` | consume-mode placeholders: supplies `cluster_name` and `existing_database_cluster_id` |
| `backend.hcl.example` | Spaces-as-S3 backend configuration |

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars   # or consume.tfvars.example
cp backend.hcl.example      backend.hcl
# edit both, replacing every placeholder

export AWS_ACCESS_KEY_ID=<spaces-access-id>
export AWS_SECRET_ACCESS_KEY=<spaces-secret-key>
terraform init -backend-config=backend.hcl
```

The state bucket must already exist; bootstrap it with [`providers/digitalocean/state-bucket`](../../modules/providers/digitalocean/state-bucket).

- **Greenfield:** apply in two passes, because the `kubernetes` and `helm` providers need the cluster. Run `terraform apply -target=module.substrate.module.cluster`, then `terraform apply`.
- **Consume:** with `enable_cluster = false`, one `terraform apply` is enough.
- **Existing infrastructure:** follow [`docs/import-runbook.md`](../../docs/import-runbook.md).

`platform_databases` and `workload_namespaces` have no default; the tfvars examples show one answer.
