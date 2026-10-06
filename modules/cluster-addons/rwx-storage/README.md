# `cluster-addons/rwx-storage`

Cloud-agnostic [`cluster-addons/rwx-storage`](../../../docs/CONTRACTS.md#cloud-agnostic-modules-no-per-cloud-implementation-needed)
module. Installs an NFS provisioner via Helm and creates a ReadWriteMany
`StorageClass` against it. Works against any conformant Kubernetes cluster.

The canonical Xema deployment uses the StorageClass name `nfs-rwx-storage`
backed by the OpenEBS dynamic NFS provisioner — the defaults match that live
setup so an existing cluster imports as a no-op.

## Usage

```hcl
module "rwx_storage" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/rwx-storage?ref=v0.12.1"

  # Defaults already target the canonical OpenEBS dynamic NFS provisioner.
  storage_class_name        = "nfs-rwx-storage"
  storage_class_provisioner = "openebs.io/nfsrwx"

  # Swap the chart to adopt a different provisioner, e.g. csi-driver-nfs:
  # chart_repository          = "https://kubernetes-sigs.github.io/csi-driver-nfs"
  # chart_name                = "csi-driver-nfs"
  # storage_class_provisioner = "nfs.csi.k8s.io"
}
```

## Consuming a pre-installed provisioner

If the cluster **already** has an NFS provisioner (e.g. hand-installed), set
`manage_provisioner_chart = false` to manage **only** the StorageClass and leave
the existing Helm release alone. This avoids adopting a drift-prone Helm release
into Terraform state — you import just the StorageClass:

```hcl
module "rwx_storage" {
  source                    = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/rwx-storage?ref=v0.12.1"
  manage_provisioner_chart  = false           # consume the existing provisioner
  storage_class_provisioner = "openebs.io/nfsrwx"
  allow_volume_expansion    = false           # match the live class
}
```

## Notes

- The `helm` and `kubernetes` providers are configured by the **root/stack**,
  not here (see [CONVENTIONS.md](../../../docs/CONVENTIONS.md)).
- `manage_provisioner_chart` (default `true`) gates the Helm release; when
  `false` the chart_* inputs are inert and only the StorageClass is created.
- `chart_repository` / `chart_name` / `chart_version` / `namespace` /
  `release_name` are all variables so adopters can swap the OpenEBS dynamic NFS
  provisioner for `csi-driver-nfs` or any other RWX backend without forking the
  module.
- The StorageClass `depends_on` the Helm release so the provisioner is
  registered before the class is created.

## Importing

- **StorageClass** — the import id is the StorageClass **name**:
  ```
  terraform import module.rwx_storage.kubernetes_storage_class_v1.this nfs-rwx-storage
  ```
- **Helm release** — the import id is `"<namespace>/<release>"`:
  ```
  terraform import module.rwx_storage.helm_release.this openebs/openebs-nfs-provisioner
  ```

| Input | Required | Description |
| --- | --- | --- |
| `chart_repository`, `chart_name`, `chart_version` | no | which provisioner chart to install (defaults: OpenEBS dynamic NFS) |
| `namespace`, `create_namespace`, `release_name` | no | Helm release placement |
| `chart_values`, `chart_set` | no | Helm value overrides |
| `storage_class_name` | no | StorageClass name (default `nfs-rwx-storage`) |
| `storage_class_provisioner`, `storage_class_parameters` | no | provisioner id + params (must match the chart) |
| `volume_binding_mode`, `reclaim_policy` | no | closed-set, validated (default `Immediate` / `Delete`) |
| `allow_volume_expansion`, `is_default_class`, `storage_class_labels` | no | StorageClass behaviour + metadata |

Outputs: `storage_class_name`, `release_name`, `namespace`.
