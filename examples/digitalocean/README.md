# Example — DigitalOcean substrate root

A runnable root that calls the
[`stacks/digitalocean/xema-substrate`](../../stacks/digitalocean/xema-substrate)
stack with placeholder values. Copy it into your operator's **private** config
root and replace the placeholders — nothing real ever lands in this public repo.

## Two modes

The stack is **independently toggleable** per substrate area via `enable_*`
inputs (all default to `true`). This root supports both modes:

1. **Greenfield (default).** Enable everything — the stack CREATES the cluster,
   managed Postgres, DNS zone, in-cluster addons, and the realm. Use
   `terraform.tfvars.example`.
2. **Consume (xema-specific).** Set `enable_cluster = false`,
   `enable_managed_postgres = false`, and `enable_dns = false` when a SEPARATE
   "cloud substrate" Terraform already owns the cluster / DB / DNS. This root then
   manages ONLY the xema-specific resources (RWX storage, namespaces, realm,
   extension claims) and CONSUMES the existing cluster by name. Use
   `consume.tfvars.example` (supplies `cluster_name` to read the existing cluster
   and `existing_database_cluster_id` to host extension databases).

## Files

| File | Purpose |
| --- | --- |
| `main.tf` | calls `module "substrate"`, declares the `backend "s3"` (partial) + outputs |
| `variables.tf` | every input passed through to the stack (incl. the `enable_*` toggles) |
| `terraform.tfvars.example` | GREENFIELD FAKE placeholder values incl. a small `extensions = {…}` example |
| `consume.tfvars.example` | CONSUME-mode FAKE placeholders: cloud infra disabled, existing cluster read by name |
| `backend.hcl.example` | DO-Spaces-as-S3 partial backend config |

## Run

```sh
# 1. Materialize the git-ignored real files from the examples.
#    Greenfield: cp terraform.tfvars.example terraform.tfvars
#    Consume:    cp consume.tfvars.example     terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example      backend.hcl
# ...then edit both, replacing every REPLACE_ME / placeholder with real values.

# 2. Spaces (S3-compatible) credentials for the state backend come from env:
export AWS_ACCESS_KEY_ID=<spaces-access-id>
export AWS_SECRET_ACCESS_KEY=<spaces-secret-key>

# 3. Init against the remote backend (state bucket must already exist — bootstrap
#    it once with modules/providers/digitalocean/state-bucket; see docs/CONVENTIONS.md).
terraform init -backend-config=backend.hcl
```

## Greenfield: two-phase apply (greenfield mode ONLY)

In **greenfield** mode (`enable_cluster = true`) the `kubernetes` and `helm`
providers are configured from the cluster's outputs, so on a **fresh** deployment
the cluster must exist before they can resolve. Apply in two passes:

```sh
terraform apply -target=module.substrate.module.cluster   # phase 1: cluster
terraform apply                                            # phase 2: everything
```

See the stack README's
[two-phase apply section](../../stacks/digitalocean/xema-substrate/README.md#critical--two-phase-apply-on-a-greenfield-cluster-greenfield-mode-only)
for the full rationale and the alternative split-root approach.

## Consume mode: single-pass apply

In **consume** mode (`enable_cluster = false`) the cluster is **read** by name via
a data source, so its outputs are known before the `kubernetes`/`helm` providers
configure — there is no two-phase ordering problem. Apply in one pass:

```sh
terraform apply
```

The stack reads the existing cluster (`cluster_name`), installs the RWX storage +
namespaces on it, manages the realm, and creates extension databases on
`existing_database_cluster_id`. It creates no cluster, DB, or DNS zone.

## Existing infrastructure (import)

When greenfield-created resources already exist, **adopt** them instead — write
`import {}` blocks and gate on a zero-change plan. The two-phase caveat does not
apply on the import path. Follow [`../../docs/import-runbook.md`](../../docs/import-runbook.md).

## Extensions

The example `extensions = {…}` block shows two biomes claiming dedicated
substrate — one object bucket + one managed database. Most biomes need **no**
entry. See [`../../docs/extensions.md`](../../docs/extensions.md).
