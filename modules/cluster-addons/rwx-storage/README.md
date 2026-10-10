# cluster-addons/rwx-storage

Installs an NFS provisioner with Helm and creates a ReadWriteMany `StorageClass` against it. It works on any conformant Kubernetes cluster. The defaults use the OpenEBS dynamic NFS provisioner and the class name `nfs-rwx-storage`.

## When to use it

Use it when workloads need ReadWriteMany volumes. Set `manage_provisioner_chart = false` to create only the `StorageClass` when a provisioner is already installed.

## Usage

```hcl
module "rwx_storage" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/rwx-storage?ref=v0.13.0"
}
```

To use another provisioner, set `chart_repository`, `chart_name` and `storage_class_provisioner` (for example `csi-driver-nfs` with `nfs.csi.k8s.io`). The `helm` and `kubernetes` providers are configured by the root.

Import ids: the `StorageClass` name, and `<namespace>/<release>` for the Helm release.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `manage_provisioner_chart` | no | Whether this module installs/manages the NFS provisioner Helm release. |
| `chart_repository` | no | Helm repository URL for the NFS provisioner chart. |
| `chart_name` | no | Helm chart name for the NFS provisioner (e.g, "nfs-provisioner" or "csi-driver-nfs"). |
| `chart_version` | no | Pinned Helm chart version. |
| `namespace` | no | Namespace the NFS provisioner Helm release is installed into. |
| `create_namespace` | no | Whether the Helm release should create its target namespace if it does not already exist. |
| `release_name` | no | Helm release name for the NFS provisioner. |
| `chart_values` | no | Inline Helm values for the provisioner chart, merged on top of chart defaults. |
| `chart_set` | no | Scalar Helm --set overrides for the provisioner chart, keyed by value path (e.g, { "replicaCount" = "1"... |
| `storage_class_name` | no | Name of the ReadWriteMany StorageClass to create. |
| `storage_class_provisioner` | no | The provisioner field on the StorageClass. |
| `storage_class_parameters` | no | Parameters passed to the StorageClass provisioner (provisioner-specific, e.g, the backing StorageClass / NF... |
| `volume_binding_mode` | no | StorageClass volumeBindingMode. |
| `reclaim_policy` | no | StorageClass reclaimPolicy. |
| `allow_volume_expansion` | no | Whether PVCs bound to this StorageClass may be expanded. |
| `is_default_class` | no | Mark this StorageClass as the cluster default (sets the storageclass.kubernetes.io/is-default-class annotat... |
| `storage_class_labels` | no | Labels applied to the StorageClass metadata. |

Outputs: `storage_class_name`, `release_name`, `namespace`.
