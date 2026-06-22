# shared-templates-volume

Cross-namespace shared **templates volume** for the fast-launch reference-mount
substrate (WS3). The workspace-orchestrator writes a content-addressed skill
mirror into it once; every session worker reads it RO at launch (no per-launch
HTTP body fetch).

## Why two PV/PVC pairs

The orchestrator and the workers live in **different namespaces**
(`xema-prod` vs `xema-opencode-workers`). PVCs are namespaced and a PV binds 1:1
to a single PVC, so one PVC cannot span both. This module creates **two static
PVs that reference the same NFS export** (`nfs_server` + `nfs_export_path`) — one
bound by a PVC in each namespace. Both point at the same bytes.

This is **static** NFS binding (`storage_class_name = ""`), distinct from the
dynamic `nfs-rwx` StorageClass in [`../rwx-storage`](../rwx-storage) (1 PVC = 1
fresh volume, not shareable cross-namespace).

## Contract

- `workers_pvc_name` MUST equal `xema-pool-<SHARED_TEMPLATES_POOL_SLUG>` — the
  storage driver derives the worker mount's claim name from the slug. The
  default `xema-pool-templates-shared` pairs with `SHARED_TEMPLATES_POOL_SLUG=templates-shared`.
- `orchestrator_pvc_name` MUST equal the orchestrator helm `claimName`
  (`xema-templates-shared`), mounted at `TEMPLATES_POOL_ROOT_PATH`.

## Wiring (no apply required to author)

1. `module "shared_templates_volume" { source = "../../modules/cluster-addons/shared-templates-volume"  nfs_server = ...  nfs_export_path = ... }`
2. Orchestrator helm: volume `xema-templates-shared` at `/var/lib/xema/storage`
   (already in `charts/workspace-orchestrator-api/main.values.yaml`).
3. `SHARED_TEMPLATES_POOL_SLUG=templates-shared` on workspace-storage-pool-api
   (already in the xema-prod values).

The kubectl bring-up equivalent (for clusters not yet TF-managed) is the admin
bootstrap manifest `deployments/xema-prod/bootstrap/templates-shared-volume.yaml`
in `xema-deploy`.
