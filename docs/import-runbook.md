# Import runbook — adopting already-running substrate

When the substrate already exists (the common case for an operating deployment),
Terraform must **adopt** it, not recreate it. The acceptance gate is a
**zero-change plan**: `terraform plan` reports `0 to add, 0 to change, 0 to
destroy` (only imports). A plan that wants to replace or destroy a live cluster or
database is a bug in your HCL — fix the HCL, never apply.

This runbook is generic; a deployment's concrete resource ids live in the
operator's **private** root (see the Xema operator example at
`repos-infra/xema-deploy/terraform/live/<deployment>/imports.tf`).

## Toggles change which resources you import — and the addresses

The stack's cloud modules are `count`-gated behind `enable_*` inputs, so the
module addresses are **`count`-indexed**: a created cluster is at
`module.cluster[0]…`, the managed DB at `module.postgres[0]…`, the DNS module at
`module.dns[0]…`, and so on. Write `import {}` block `to =` addresses with the
`[0]` index whenever the owning module is enabled.

In **consume** mode (`enable_cluster = false`,
`enable_managed_postgres = false`, `enable_dns = false`) the cluster, managed
database, and DNS zone are **consumed, not imported** — they are owned by a
separate "cloud substrate" Terraform. The cluster is read via
`data.digitalocean_kubernetes_cluster.existing` (by `var.cluster_name`), not a
managed resource, so there is **nothing to import** for it. You only import the
in-cluster and identity resources that this deployment owns: the RWX `StorageClass` /
`helm_release`, the workload namespaces, the realm (+ clients/roles/mappers), and
any extension databases/buckets already created on the shared cluster.

## Order

1. **Bootstrap state** (once). Create the remote state bucket out-of-band, then
   configure the backend. See [CONVENTIONS.md § State & secrets](CONVENTIONS.md).
   This avoids a chicken-and-egg where the backend needs a bucket that Terraform
   would otherwise manage in the same state.

2. **`terraform init`** against the remote backend.

3. **Write `import {}` blocks** for every live resource. Terraform 1.6 supports
   config-driven import:

   ```hcl
   import {
     # NOTE: module.cluster is count-gated → addresses carry the [0] index.
     to = module.substrate.module.cluster[0].digitalocean_kubernetes_cluster.this
     id = "<doks-cluster-uuid>"
   }
   ```

   (In consume mode the cluster is read via a data source, not managed — skip its
   import block entirely; same for the managed DB and DNS zone.)

   Collect the real ids from the cloud first (never guess). For DigitalOcean:

   | Resource | How to find the id |
   | --- | --- |
   | DOKS cluster | `doctl kubernetes cluster list` → `ID` |
   | Node pool | `doctl kubernetes cluster node-pool list <cluster-id>` → `<cluster-id>,<pool-id>` |
   | VPC | `doctl vpcs list` |
   | Managed Postgres | `doctl databases list` → `ID` |
   | DNS domain / record | `doctl compute domain list` / `doctl compute domain records list <domain>` → `<domain>,<record-id>` |
   | Spaces bucket | bucket name |

   For in-cluster addons (`kubernetes_storage_class_v1`, `kubernetes_namespace_v1`) the id
   is the object name. For a `helm_release`, the id is `<namespace>/<release>`. For
   the Keycloak realm the id is the realm name; clients/roles/mappers follow the
   `terraform-provider-keycloak` import syntax.

4. **`terraform plan`** → expect `N to import, 0 to add, 0 to change, 0 to
   destroy`. If anything shows `~ change` or `-/+ replace`, **reconcile the HCL** to
   match the live resource's actual attributes until the diff is empty. Common
   causes: a default that differs from the live value, an attribute the live
   resource sets that your HCL omits, or tags/labels drift.

5. **`terraform apply`** (import only). Re-run **`terraform plan`** → it **must**
   report `No changes`. That empty plan is the proof the substrate is now
   declaratively owned with zero drift.

6. **Tip:** `terraform plan -generate-config-out=generated.tf` scaffolds HCL from
   the live resource for each `import` block — a useful starting point you then
   trim to the module's variables.

## Hard rules

- Never `apply` a plan that destroys or replaces a live cluster, database, or DNS
  zone. There is no acceptable reason during adoption.
- Import the smallest blast-radius resources first (namespaces, storage class),
  prove the loop, then import the cluster and database.
- The Keycloak realm is shared with other (non-Xema) realms on the same server —
  scope the `identity-realm` module to the deployment's realm only; never import or
  manage the shared/master realm.
