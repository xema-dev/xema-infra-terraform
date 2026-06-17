# `cluster-addons/workload-namespaces`

Cloud-agnostic [`cluster-addons/workload-namespaces`](../../../docs/CONTRACTS.md#cloud-agnostic-modules-no-per-cloud-implementation-needed)
module. Ensures the namespaces that must exist **before** the Helm application
bring-up runs. These are PREREQUISITES — the app bring-up assumes they are
present and does not create them.

The default set matches the canonical Xema deployment, so an existing cluster
imports as a no-op.

## Usage

```hcl
module "workload_namespaces" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/workload-namespaces?ref=v0.1.0"

  # Defaults to the canonical 7-namespace set. Override to adopt elsewhere.
  # namespaces = ["xema-prod", "shared-prod", ...]

  labels = {
    "xema-prod" = { "team" = "platform" }
  }
}
```

## Notes

- The `kubernetes` provider is configured by the **root/stack**, not here (see
  [CONVENTIONS.md](../../../docs/CONVENTIONS.md)).
- Default `namespaces`: `xema-prod`, `shared-prod`, `xema-infra`,
  `xema-opencode-workers`, `xema-biome-sidecars`, `xema-biome-apis`,
  `xema-image-builders`.
- `labels` is keyed by namespace name; a namespace absent from the map simply
  gets no extra labels.

## Importing

The import id for each namespace is the namespace **name**. Because the resource
is a `for_each` over the set, address it by key:

```
terraform import 'module.workload_namespaces.kubernetes_namespace.this["xema-prod"]' xema-prod
```

| Input | Required | Description |
| --- | --- | --- |
| `namespaces` | no | the prerequisite namespaces (default: canonical 7) |
| `labels` | no | optional per-namespace labels keyed by name |

Outputs: `namespaces` (the set of ensured names).
