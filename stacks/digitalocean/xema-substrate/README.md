# `xema-substrate` stack — DigitalOcean

Composes the full Xema substrate on DigitalOcean from the per-cloud primitives
and the cloud-agnostic addons:

| Module | What it provisions |
| --- | --- |
| `module.cluster` | DOKS managed Kubernetes cluster + node pools |
| `module.postgres` | DO managed Postgres + logical databases/roles |
| `module.dns` | the managed DNS zone's records |
| `module.rwx_storage` | a ReadWriteMany `StorageClass` (NFS provisioner) on the cluster |
| `module.workload_namespaces` | the namespaces the Helm app bring-up expects |
| `module.identity_realm` | the Keycloak realm (realm + clients + roles + mappers) |
| `module.extension_bucket` | dedicated object buckets claimed by biomes (see below) |

It configures all four providers (`digitalocean`, `kubernetes`, `helm`,
`keycloak`) in `providers.tf` — reusable modules never declare a `provider {}`
block, so the root owns provider config and passes it down.

## Two modes — greenfield vs consume

Every area of the substrate is **independently toggleable** via an `enable_*`
input (all default to `true`). This lets the same stack run in two modes:

1. **Greenfield (create everything — the default).** `enable_cluster`,
   `enable_managed_postgres`, and `enable_dns` are all `true`, so the stack
   **creates** the cluster, the managed Postgres, the DNS zone records, the
   in-cluster addons, and the Keycloak realm — the complete substrate from
   nothing.
2. **Xema-specific / consume.** Set `enable_cluster = false`,
   `enable_managed_postgres = false`, and `enable_dns = false` when a **separate
   "cloud substrate" Terraform** (owned by another team/agent) already owns the
   cluster, managed database, and DNS zone. In this mode the stack manages **only
   the xema-specific resources** — RWX storage, workload namespaces, the Keycloak
   realm, and extension/biome claims — and **consumes** the existing cluster: when
   `enable_cluster = false` it reads the cluster by name (`var.cluster_name`) via
   `data.digitalocean_kubernetes_cluster.existing` to configure the
   `kubernetes`/`helm` providers, and extension `managed_databases` claims target
   `var.existing_database_cluster_id`.

A disabled cloud module is `count`-gated to zero — the stack **consumes** the
existing resource instead of creating it; it never plans a destroy.

### `enable_*` toggles

| Input | Default | What it gates |
| --- | --- | --- |
| `enable_cluster` | `true` | Create the DOKS cluster. `false` ⇒ read the existing one by `var.cluster_name` for the in-cluster providers. |
| `enable_managed_postgres` | `true` | Create the managed Postgres cluster. `false` ⇒ extension databases target `var.existing_database_cluster_id`. |
| `enable_dns` | `true` | Manage the DNS zone + records. `false` ⇒ DNS owned elsewhere (extension `dns_records` then fail fast). |
| `enable_rwx_storage` | `true` | Install the RWX `StorageClass` + NFS provisioner on the (created or consumed) cluster. |
| `enable_workload_namespaces` | `true` | Ensure the workload namespaces exist on the (created or consumed) cluster. |
| `enable_identity_realm` | `true` | Manage the Keycloak realm (realm + clients + roles + mappers). |

In consume mode, `cluster_name` (to read the existing cluster) and
`existing_database_cluster_id` (to host extension databases on the shared cluster)
are the two extra inputs that replace the create-time cluster/DB inputs.

## Extension / biome claims

`var.extensions` is a map keyed by biome id; each value may carry any subset of a
**closed set** of three claim kinds — `object_buckets`, `managed_databases`,
`dns_records`. `extensions.tf` flattens each kind into a `"<biome>/<claim>"`-keyed
map and wires it to the cloud primitive:

- `object_buckets` → `module.extension_bucket` (`for_each`).
- `managed_databases` → a `digitalocean_database_db` (+ optional
  `digitalocean_database_user`) on the **resolved** managed-Postgres cluster — the
  created `module.postgres`, or `var.existing_database_cluster_id` when consuming a
  shared cluster. It fails fast if neither resolves a cluster.
- `dns_records` → merged into `module.dns.records` (requires `enable_dns`; fails
  fast otherwise).

This is an **escape hatch** for biomes that need DEDICATED, out-of-cluster
substrate only. Shared-schema biomes need no entry here — they are provisioned at
runtime by the platform's biome installer. Full contract:
[`../../../docs/extensions.md`](../../../docs/extensions.md).

## CRITICAL — two-phase apply on a greenfield cluster (greenfield mode ONLY)

This caveat applies **only when `enable_cluster = true`** (greenfield mode). In
consume mode (`enable_cluster = false`) it does **not** apply — see the note at the
end of this section.

The `kubernetes` and `helm` providers are configured from
`module.cluster`'s outputs (`endpoint`, `token`, `cluster_ca_certificate`). On a
**greenfield** apply the cluster does not exist yet, so those provider arguments
are unknown until the cluster is created. Terraform cannot configure a provider
from a not-yet-known value in a single pass. Apply in two phases:

```sh
# Phase 1 — create the cluster (and anything it doesn't depend on the k8s/helm
# providers for) first, so its outputs become known.
terraform apply -target=module.cluster

# Phase 2 — full apply; the kubernetes/helm providers now resolve from the live
# cluster, and the addons (rwx_storage, workload_namespaces) provision.
terraform apply
```

Alternatively, split into two root configurations — a "cluster" root and an
"in-cluster" root that reads the cluster via a remote-state data source — if you
prefer never to use `-target`. Either approach is valid; pick one per deployment
and document it in the operator's private root.

**Consume mode does not hit this caveat.** When `enable_cluster = false` the
cluster is **read** via `data.digitalocean_kubernetes_cluster.existing` (by
`var.cluster_name`), so its endpoint/token/CA are known before the
`kubernetes`/`helm` providers configure — there is no not-yet-known ordering
problem and the full apply runs in a single pass. This is the verified
xema-specific operating mode: with the cloud modules disabled the stack read the
live DOKS cluster and adopted the `xema-prod` namespace on a zero-change plan.

**The IMPORT path also does not hit this caveat.** When the whole substrate
already exists (greenfield resources adopted rather than created) every resource —
including the cluster — is adopted via `import {}` blocks in a single plan/apply,
so the cluster outputs are known from existing state and the providers configure
cleanly. Follow [`../../../docs/import-runbook.md`](../../../docs/import-runbook.md)
and gate on a zero-change plan.

## Usage

This stack is consumed by a root such as [`examples/digitalocean`](../../../examples/digitalocean).
Reusable stacks carry no `backend {}` block — the consuming root owns the backend.
See [`../../../docs/CONVENTIONS.md`](../../../docs/CONVENTIONS.md) for state & secret rules.
