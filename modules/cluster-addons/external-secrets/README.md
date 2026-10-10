# cluster-addons/external-secrets

Installs the [External Secrets Operator](https://external-secrets.io) and one namespaced `SecretStore` per namespace of each secret trust boundary, backed by Azure Key Vault through workload identity.

## When to use it

Use it to give workloads secrets from Key Vault. There is no cluster-wide store, so one namespace cannot read another boundary's secrets.

## Usage

```hcl
module "external_secrets" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/external-secrets?ref=v0.13.0"

  region              = "westeurope"
  resource_group_name = "rg-example"
  oidc_issuer_url     = module.cluster.oidc_issuer_url

  secret_stores = {
    app = {
      namespaces   = ["ns-a", "ns-b"]
      key_vault_id = "<vault resource id>"
      vault_uri    = "https://<vault>.vault.azure.net/"
    }
  }
}
```

For each boundary and namespace the module creates a user-assigned identity with one federated credential, a `Key Vault Secrets User` assignment on that boundary's vault only, a service account and a `SecretStore` named `secret_store_name`. `ExternalSecret`s reference it with `secretStoreRef: { kind: SecretStore, name: platform }`. The namespaces must already exist. No two boundaries may share a namespace or a key vault.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `chart_version` | no | Pinned external-secrets chart version (https://charts.external-secrets.io). |
| `namespace` | no | Namespace the operator is installed into (created if absent). |
| `values` | no | Extra inline Helm values for external-secrets, merged AFTER the module's own. |
| `secret_stores` | no | One entry per secret trust boundary, keyed by a boundary name of the caller's choosing. |
| `secret_store_name` | no | Name of the namespaced SecretStore created in each boundary namespace (what ExternalSecret resources refere... |
| `store_service_account_name` | no | Name of the service account created in each boundary namespace; the subject its identity is federated to. |
| `identity_name_prefix` | no | Prefix of each managed identity name ("<prefix>-<boundary>-<namespace>"): one identity per (boundary, nam... |
| `region` | yes | Azure location of the identities (e.g, "westeurope"). |
| `resource_group_name` | yes | Existing resource group the identities are created in. |
| `oidc_issuer_url` | yes | The cluster's OIDC issuer URL (providers/azure/cluster output) the identities are federated to. |
| `tags` | no | Tags applied to every created Azure resource. |
| `known_namespaces` | no | When set, the namespaces the caller creates; every boundary namespace must be one of them (the SecretStores... |

Outputs: `assigned_role_names`, `secret_store_name`, `namespace`, `secret_stores`.
