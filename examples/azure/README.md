# Example — Azure substrate root

A runnable root that calls the
[`stacks/azure/xema-substrate`](../../stacks/azure/xema-substrate) stack with
placeholder values. Copy it into your operator's **private** config root and
replace the placeholders — nothing real ever lands in this public repo.

Everything is derived from `deployment_name` (`acme-dev` in the examples):
cluster `acme-dev-aks`, server `acme-dev-pg`, storage account `acmedevblob`,
vault `acme-dev-kv`, namespaces `acme-dev`, `acme-dev-shared`, …, databases
`acme_dev_identity_api`, …, roles `acme_dev` / `acme_dev_provisioner`. See the
[stack README](../../stacks/azure/xema-substrate/README.md#derived-names).

Four of those names are unique across **every** Azure tenant (the vault, the
storage account, the Flexible Server, the cache), so each has an optional
override — `key_vault_name`, `storage_account_name`, `postgres_server_name`,
`redis_cache_name` — for when the derived name is already taken; see
[Overriding the globally-unique names](../../stacks/azure/xema-substrate/README.md#overriding-the-globally-unique-names).
The two in-cluster names your own manifests reference, the ClusterIssuer
(`cluster_issuer_name`, default `letsencrypt`) and the ClusterSecretStore
(`cluster_secret_store_name`, default `platform`), are inputs here and come
back as outputs of the same name — read them from `terraform output` rather
than restating them.

## Two modes

1. **Greenfield (default).** Enable everything — the stack CREATES the cluster,
   Flexible Server, DNS zone, blob account, Key Vault, in-cluster addons and
   the realm. Use `terraform.tfvars.example`.
2. **Consume (xema-specific).** Set `enable_cluster = false`,
   `enable_managed_postgres = false`, and `enable_dns = false` when a SEPARATE
   "cloud substrate" Terraform already owns them. This root then manages ONLY
   the xema-specific resources and CONSUMES the existing cluster by name. Use
   `consume.tfvars.example`.

## Files

| File | Purpose |
| --- | --- |
| `main.tf` | calls `module "substrate"`, declares the `backend "azurerm"` (partial) + outputs |
| `variables.tf` | every input passed through to the stack (incl. the `enable_*` toggles) |
| `terraform.tfvars.example` | GREENFIELD FAKE placeholder values incl. a small `extensions = {…}` example |
| `consume.tfvars.example` | CONSUME-mode FAKE placeholders: cloud infra disabled, existing cluster read by name |
| `backend.hcl.example` | Azure-Storage partial backend config |

## Run

```sh
# 1. Materialize the git-ignored real files from the examples.
#    Greenfield: cp terraform.tfvars.example terraform.tfvars
#    Consume:    cp consume.tfvars.example     terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example      backend.hcl
# ...then edit both, replacing every REPLACE_ME / placeholder with real values.

# 2. Authenticate to Azure (the provider chain; nothing is an input):
az login && az account set --subscription <id>   # or ARM_* / OIDC

# 3. Secrets never touch a file:
export TF_VAR_key_vault_secrets='{"postgres-app-password":"..."}'

# 4. Init against the remote backend (state account must already exist —
#    bootstrap it once with modules/providers/azure/state-bucket).
terraform init -backend-config=backend.hcl
```

## Greenfield: apply in phases (greenfield mode ONLY)

The `kubernetes`, `helm` and `postgresql` providers connect to things this
stack creates, so a fresh deployment applies in phases:

```sh
terraform apply -target=module.substrate.module.cluster \
                -target=module.substrate.module.postgres \
                -target=module.substrate.module.dns \
                -target=module.substrate.module.blob \
                -target=module.substrate.module.secrets_backend   # phase 1: cloud infra
terraform apply                                                   # phase 2: in-cluster + roles
# phase 3: after the Helm bring-up, set enable_identity_realm = true and apply again
```

The Postgres roles need the operator to **reach** the server: private access
(the default) means a VPN/bastion/runner inside the VNet. See the stack README's
[apply-order section](../../stacks/azure/xema-substrate/README.md#apply-order-on-a-greenfield-cluster-read-this).

## Consume mode: single-pass apply

With `enable_cluster = false` the cluster is **read** by name, so its facts are
known before the providers configure: `terraform apply` in one pass. It creates
no cluster, server or zone; extension databases land on
`existing_postgres_server_id`.

## Existing infrastructure (import)

When greenfield-created resources already exist, **adopt** them instead — write
`import {}` blocks and gate on a zero-change plan. Follow
[`../../docs/import-runbook.md`](../../docs/import-runbook.md).

## Extensions

The example `extensions = {…}` block shows two biomes claiming dedicated
substrate — one storage account + one managed database. Most biomes need **no**
entry. See [`../../docs/extensions.md`](../../docs/extensions.md).
