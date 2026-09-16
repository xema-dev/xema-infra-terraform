# `cluster-addons/shared-templates-volume`

A **ReadWriteMany NFS export shared across N namespaces**: one namespace owns
the tree (its workload writes it), any number of other namespaces mount the
same bytes (their workloads read it). The module knows nothing about what the
tree holds or who writes it — those are the consumer's facts, passed as inputs.

## Why one PV/PVC pair per namespace

PVCs are namespaced and a PV binds 1:1 to a single PVC, so one PVC cannot span
namespaces. This module creates **one static PV + PVC pair per namespace** —
the owner's and one per consumer — every PV referencing the **same NFS export**
(`nfs_server` + `nfs_export_path`). Each PV is pre-bound (`claim_ref`) to its
claim, so nothing can cross-bind.

This is **static** NFS binding (`storage_class_name = ""`), distinct from the
dynamic ReadWriteMany StorageClass in [`../rwx-storage`](../rwx-storage) (1 PVC
= 1 fresh volume, not shareable across namespaces).

## Inputs

| Input | Required | Description |
| --- | --- | --- |
| `nfs_server` | **yes** | host/IP of the NFS server backing the export |
| `nfs_export_path` | **yes** | the export path; every PV references this identical path |
| `owner_namespace` | **yes** | the namespace that OWNS the export (its workload writes it) |
| `owner_pvc_name` | **yes** | the claim created there — must equal the `claimName` the owning workload references |
| `consumer_mounts` | **yes** | the namespaces that MOUNT the export, keyed by namespace, each value the claim name to create there (at least one; the owner may not appear) |
| `name_prefix` | **yes** | prefix for the cluster-scoped PV names: `<prefix>-owner`, `<prefix>-consumer-<namespace>` |
| `capacity` | no | requested size on every PV/PVC (`50Gi`; NFS does not enforce it) |
| `mount_options` | no | NFS mount options on every PV (`["nfsvers=4.1"]`) |
| `labels` | no | labels on every PV/PVC |

Outputs: `owner_pvc_name`, `consumer_pvc_names` (keyed by namespace),
`persistent_volume_names`.

## Usage

```hcl
module "shared_export" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/shared-templates-volume?ref=v1.0.0"

  nfs_server      = "10.0.0.5"
  nfs_export_path = "/exports/shared-tree"

  # EXAMPLE names — yours come from the workloads that mount the export.
  owner_namespace = "acme-prod"
  owner_pvc_name  = "shared-tree"
  consumer_mounts = {
    "acme-workers" = "shared-tree-ro"
  }
  name_prefix = "acme-shared-tree"
}
```

The claim names are a contract between this module and the workloads that
mount the export: a workload references its claim by name, so the name passed
here must be the one that workload expects. Read the names back from the
outputs rather than restating them.

The `kubernetes` provider is configured by the **root/stack**, not here (see
[CONVENTIONS.md](../../../docs/CONVENTIONS.md)).
