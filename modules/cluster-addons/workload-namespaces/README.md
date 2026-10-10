# cluster-addons/workload-namespaces

Ensures a roster of namespaces exists before anything deploys into them, with optional labels.

## When to use it

Use it for namespaces that must exist before workloads are applied. The roster is a required input with no default. Label and annotation drift on an existing namespace is ignored, so adopting one by import is clean.

## Usage

```hcl
module "workload_namespaces" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/workload-namespaces?ref=v1.0.0"

  namespaces = ["acme-prod", "acme-infra"]
  labels     = { "acme-prod" = { team = "platform" } }
}
```

Import with `terraform import 'module.workload_namespaces.kubernetes_namespace_v1.this["acme-prod"]' acme-prod`. The `kubernetes` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `namespaces` | yes | The namespaces to ensure exist, by full name. |
| `labels` | no | Optional per-namespace labels, keyed by namespace name. |

Outputs: `namespaces`.
