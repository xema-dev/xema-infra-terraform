# cluster-addons/shared-templates-volume

Shares one ReadWriteMany NFS export across several namespaces: one namespace owns it and writes, any number of others mount the same data.

## When to use it

Use it when several namespaces need the same NFS tree. A claim cannot span namespaces, so the module creates one static PV and PVC pair per namespace, all pointing at the same export and pre-bound to their claim. For per-claim dynamic volumes use [`rwx-storage`](../rwx-storage).

## Usage

```hcl
module "shared_export" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/shared-templates-volume?ref=v1.0.0"

  nfs_server      = "10.0.0.5"
  nfs_export_path = "/exports/shared-tree"
  owner_namespace = "acme-prod"
  owner_pvc_name  = "shared-tree"
  consumer_mounts = { "acme-workers" = "shared-tree-ro" }
  name_prefix     = "acme-shared-tree"
}
```

Workloads reference their claim by name, so use the names from the outputs. The `kubernetes` provider is configured by the root.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `nfs_server` | yes | Host/IP of the NFS server backing the shared export (the same backend family as the cluster's ReadWriteMany... |
| `nfs_export_path` | yes | NFS export path dedicated to the shared tree. |
| `owner_namespace` | yes | The namespace that OWNS the shared export — the one whose workload writes it. |
| `owner_pvc_name` | yes | Name of the PersistentVolumeClaim created in owner_namespace. |
| `consumer_mounts` | yes | The namespaces that MOUNT the shared export, keyed by namespace name, each value the PersistentVolumeClaim... |
| `name_prefix` | yes | Prefix for the static PersistentVolume names: `<prefix>-owner` and `<prefix>-consumer-<namespace>`. |
| `capacity` | no | Requested capacity for the static PVs/PVCs (NFS ignores it for enforcement, but Kubernetes requires a value). |
| `mount_options` | no | NFS mount options applied to every PV. |
| `labels` | no | Labels applied to every PV and PVC this module creates. |

Outputs: `owner_pvc_name`, `consumer_pvc_names`, `persistent_volume_names`.
