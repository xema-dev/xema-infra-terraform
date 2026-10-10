# cluster-addons/secrets

Creates operator-provided credentials as Kubernetes Secrets on the target cluster. Helm values reference them with `secretKeyRef`. The Secret names are the stable contract.

## When to use it

Use it for credentials a cluster needs before any secrets backend exists. The namespaces must already exist (see [`workload-namespaces`](../workload-namespaces)). It uses only the `kubernetes` provider.

## Usage

```hcl
module "secrets" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/secrets?ref=v0.13.0"

  secrets = {
    registry_mirror = {
      namespace = "cattle-system"
      type      = "kubernetes.io/dockerconfigjson"
      data      = { ".dockerconfigjson" = var.registry_dockerconfigjson }
    }
  }
}
```

The `secrets` input is sensitive. Pass values through `TF_VAR_*` or a decrypted tfvars file that is never committed. The import id of a Secret is `<namespace>/<name>`.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `secrets` | no | Operator-provided credentials to materialize as Kubernetes Secrets, keyed by a stable id. |

Outputs: `secret_names`, `namespaces`.
