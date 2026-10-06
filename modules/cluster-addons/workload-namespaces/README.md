# `cluster-addons/workload-namespaces`

Cloud-agnostic [`cluster-addons/workload-namespaces`](../../../docs/CONTRACTS.md#cloud-agnostic-modules-no-per-cloud-implementation-needed)
module. Ensures a roster of namespaces exists **before** anything applies
workloads to the cluster. The namespaces are PREREQUISITES — whatever deploys
into them afterwards assumes they are present and does not create them.

The roster is a **required input with no default**. Which namespaces a
deployment runs in is a fact the consumer derives from what it deploys; this
module deals in the capability (namespaces exist, with labels, adoptable by
import) and knows nothing about who lives in them.

## Usage

```hcl
module "workload_namespaces" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/workload-namespaces?ref=v1.0.0"

  # EXAMPLE roster — yours comes from your own deployment, not from here.
  namespaces = ["acme-prod", "acme-shared", "acme-infra", "acme-workers"]

  labels = {
    "acme-prod" = { "team" = "platform" }
  }
}
```

## Notes

- The `kubernetes` provider is configured by the **root/stack**, not here (see
  [CONVENTIONS.md](../../../docs/CONVENTIONS.md)).
- `labels` is keyed by namespace name; a namespace absent from the map simply
  gets no extra labels. Label and annotation drift on an existing namespace is
  ignored, so adopting one is a clean import rather than a strip of metadata
  other controllers wrote.

## Importing

The import id for each namespace is the namespace **name**. Because the resource
is a `for_each` over the set, address it by key:

```
terraform import 'module.workload_namespaces.kubernetes_namespace_v1.this["acme-prod"]' acme-prod
```

| Input | Required | Description |
| --- | --- | --- |
| `namespaces` | **yes** | the roster of namespaces to ensure (DNS-1123 labels; at least one) |
| `labels` | no | optional per-namespace labels keyed by name |

Outputs: `namespaces` (the set of ensured names).
