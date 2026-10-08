# `cluster-addons/external-secrets`

The [External Secrets Operator](https://external-secrets.io) and one namespaced `SecretStore` per
namespace of each secret trust boundary. Backend: Azure Key Vault through workload identity.

**There is no cluster-wide store.** A `ClusterSecretStore` reads one vault through one identity for
every namespace, so any namespace could create an `ExternalSecret` for another boundary's secrets.
Instead, `secret_stores` is a map keyed by boundary name (a deployment, the infrastructure
authority, a shared deployment, ...):

```hcl
secret_stores = {
  <boundary> = {
    namespaces   = ["ns-a", "ns-b"]
    key_vault_id = "<vault resource id>"
    vault_uri    = "https://<vault>.vault.azure.net/"
  }
}
```

Per boundary the module creates its own user-assigned identity, a federated credential per
namespace (subject `system:serviceaccount:<namespace>:<store_service_account_name>`), a
`Key Vault Secrets User` assignment on ONLY that boundary's vault, and in each namespace a service
account plus a `SecretStore` named `secret_store_name` (default `platform`). `ExternalSecret`s use
`secretStoreRef: { kind: SecretStore, name: platform }`. The namespaces must already exist.

No two entries may share a namespace or a key vault; namespaces must be non-empty. These rules live
in the provider-free `./boundaries` submodule, tested on Terraform 1.6 and OpenTofu.

Separate from `cluster-addons/gateway-tls` because secrets are needed from the first workload on,
whatever serves inbound traffic.
