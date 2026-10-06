# `cluster-addons/secrets`

Cloud-agnostic. Materializes operator-provided credentials as **Kubernetes
Secrets** on the target cluster — the **management-plane secret backend**: the
source that Helm values reference via `secretKeyRef` (registry-mirror creds,
Teleport/Headscale credentials, etc.).

Works on any conformant cluster (uses the `kubernetes` provider only). The
namespaces must already exist (pair with
[`cluster-addons/workload-namespaces`](../workload-namespaces) if you need to
create them first).

> **v1 scope.** This materializes the values handed to Terraform. The Secret
> **names** are the stable contract, so it can later be swapped for an
> external-secrets-operator / Vault flow without changing the Helm consumers.

## Usage

```hcl
module "secrets" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/secrets?ref=v0.12.1"

  secrets = {
    registry_mirror = {
      namespace = "cattle-system"
      type      = "kubernetes.io/dockerconfigjson"
      data      = { ".dockerconfigjson" = var.registry_dockerconfigjson }
    }
    teleport_oidc = {
      namespace = "teleport"
      data      = { client-secret = var.teleport_oidc_client_secret }
    }
  }
}
```

The whole `secrets` input is `sensitive`. Provide values via `TF_VAR_*` env or a
sops-decrypted tfvars that is never committed.

| Input | Required | Description |
| --- | --- | --- |
| `secrets` | no (default `{}`) | map keyed by id → `{ name?, namespace, type?, data, labels? }` |

Outputs: `secret_names` (map id→name), `namespaces` (distinct list).

Import id of a Kubernetes Secret = `"<namespace>/<name>"`.
