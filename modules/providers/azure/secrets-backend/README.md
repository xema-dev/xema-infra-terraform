# providers/azure/secrets-backend

An RBAC-authorized Azure Key Vault, optionally seeded with secrets, plus an optional user-assigned identity federated to the External Secrets Operator. Implements the [`secrets-backend` contract](../../../../docs/CONTRACTS.md#secrets-backend-optional).

## When to use it

Optional. Use it to give the cluster secrets from Key Vault through workload identity, with no stored credential.

## Usage

```hcl
module "secrets" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/azure/secrets-backend?ref=v0.13.0"

  name   = "acme-dev-kv"
  region = "westeurope"

  secret_names  = ["postgres-app-password"]
  secret_values = var.key_vault_secrets
}
```

- `secret_values` is sensitive and has no default; pass it through `TF_VAR_*`. A name in `secret_names` without a value fails the plan.
- The vault uses RBAC. The deployer gets Key Vault Secrets Officer to seed secrets (after `rbac_propagation_wait`, default 30s); readers get Secrets User only.
- Feed `key_vault_id` and `vault_uri` to the [`external-secrets`](../../../cluster-addons/external-secrets) addon and leave `workload_identity.enabled = false`; that addon creates its own reader identities.
- `purge_protection_enabled` defaults to off here because it is irreversible. The substrate stack always enables it.
- The `azurerm` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `name` | yes | Key Vault name: 3-24 chars, letters/digits/hyphens, starting with a letter, globally unique as <name>.vault... |
| `region` | yes | Azure location (e.g, "westeurope"). |
| `secret_names` | no | Secrets to SEED at provisioning time, by name (Key Vault secret names: letters, digits, hyphens). |
| `secret_values` | yes | Values for every name in secret_names, keyed by name. |
| `workload_identity` | no | Federate the cluster's OIDC issuer to a user-assigned identity that may READ secrets (Key Vault Secrets Use... |
| `grant_deployer_secrets_officer` | no | Grant the principal running Terraform "Key Vault Secrets Officer" on the vault so it can write the seeded... |
| `rbac_propagation_wait` | no | How long to wait after granting the deployer role before writing secrets. |
| `seed_prerequisites` | no | Opaque values (e.g, ids) the seeded secrets must wait for: resources the caller composes AFTER the vault, s... |
| `purge_protection_enabled` | no | Key Vault purge protection. |
| `soft_delete_retention_days` | no | Soft-delete retention (7-90 days); null (default) is Azure's 90. Fixed at vault creation. |
| `public_network_access_enabled` | no | Whether the vault accepts (authenticated) traffic from the public internet. |
| `resource_group_name` | no | Existing resource group to create the vault in. |
| `tags` | no | Tags applied to every created resource. |

Outputs: `vault_uri`, `client_id`, `tenant_id`, `key_vault_id`, `secret_ids`, `resource_group_name`, `assigned_role_names`.
