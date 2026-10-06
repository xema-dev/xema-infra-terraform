# `providers/azure/secrets-backend`

Azure implementation of the [`secrets-backend` contract](../../../../docs/CONTRACTS.md#secrets-backend-optional).
An **RBAC-authorized Key Vault**, optionally seeded with secrets, plus a
user-assigned identity federated to the External Secrets Operator's service
account so the cluster reads secrets through **workload identity** — no stored
credential anywhere.

## Usage

```hcl
module "secrets" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/secrets-backend?ref=v0.13.0"

  name   = "acme-dev-kv"
  region = "westeurope"

  secret_names  = ["postgres-app-password"]
  secret_values = var.key_vault_secrets # sensitive map, from TF_VAR_* — never a file in git

  workload_identity = {
    enabled         = true
    oidc_issuer_url = module.cluster.oidc_issuer_url
  }
}
```

## Notes

- **`secret_values` has no default.** It is the one input that carries
  credential material, so it must be supplied every time; a name in
  `secret_names` with no value fails the plan naming the missing secret.
  Terraform forbids `for_each` over a sensitive map, which is why names and
  values are two inputs.
- The vault uses **RBAC** (`rbac_authorization_enabled`), never access
  policies. The deployer is granted *Key Vault Secrets Officer* to write the
  seeded secrets; the reader identity holds *Key Vault Secrets User* only.
- **`rbac_propagation_wait`** (`time_sleep`, default 30s) sits between the
  deployer grant and the first secret write. Azure RBAC is eventually
  consistent, so this is a wait on an external system's documented lag — the
  alternative is a failed first apply and a manual retry.
- Feed `vault_uri`, `client_id` and `tenant_id` to the
  [`external-secrets`](../../../cluster-addons/external-secrets/README.md) addon's
  `azure-key-vault` ClusterSecretStore.
- `purge_protection_enabled` defaults **off** because it is irreversible and
  reserves the vault name after deletion; enable it for production.
- The provider (`hashicorp/azurerm`) is configured by the **root/stack**, not
  here (see [CONVENTIONS.md](../../../../docs/CONVENTIONS.md)).

| Input | Required | Description |
| --- | --- | --- |
| `name`, `region` | yes | vault identity + location |
| `secret_values` | yes (sensitive, no default) | values for the seeded secrets |
| `secret_names` | no | which secrets to seed (default none) |
| `workload_identity` | no | mint the External Secrets reader identity |
| `grant_deployer_secrets_officer`, `rbac_propagation_wait` | no | deployer write access + its propagation wait |
| `purge_protection_enabled`, `soft_delete_retention_days`, `public_network_access_enabled` | no | vault lifecycle + reachability |
| `resource_group_name`, `tags` | no | use an existing resource group (else `"<name>-rg"`), tagging |

Outputs: `vault_uri`, `client_id`, `tenant_id`, `key_vault_id`, `secret_ids`,
`resource_group_name`.
