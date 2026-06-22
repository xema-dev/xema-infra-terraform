# Shared templates volume (fast-launch WS3 reference-mount substrate).
#
# The workspace-orchestrator (namespace `orchestrator_namespace`) writes the
# content-addressed skill mirror RW; every session worker (namespace
# `workers_namespace`) reads it RO. PVCs are namespaced and a PV binds 1:1 to a
# single PVC, so a single PVC cannot span both namespaces. We therefore create
# TWO static PVs that reference the SAME NFS export (server + path) — one bound
# by a PVC in the orchestrator namespace and one by a PVC in the workers
# namespace. Both point at the same bytes, so a skill the orchestrator
# materializes is immediately visible to every worker.
#
# This is STATIC NFS binding (storageClassName = "") — distinct from the dynamic
# nfs-rwx StorageClass in ../rwx-storage (1 PVC = 1 fresh volume, which cannot
# be shared cross-namespace). The worker-side PVC name is contract-bound to the
# storage driver: it MUST equal `xema-pool-<SHARED_TEMPLATES_POOL_SLUG>`.

locals {
  pv_orchestrator = "${var.name_prefix}-orchestrator"
  pv_workers      = "${var.name_prefix}-workers"
}

resource "kubernetes_persistent_volume" "orchestrator" {
  metadata {
    name   = local.pv_orchestrator
    labels = merge(var.labels, { "xema.io/volume" = "templates-shared" })
  }
  spec {
    capacity                         = { storage = var.capacity }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = ""
    mount_options                    = var.mount_options
    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = var.nfs_export_path
      }
    }
    # Pre-bind so the two PVs cannot cross-bind to the wrong PVC.
    claim_ref {
      namespace = var.orchestrator_namespace
      name      = var.orchestrator_pvc_name
    }
  }
}

resource "kubernetes_persistent_volume" "workers" {
  metadata {
    name   = local.pv_workers
    labels = merge(var.labels, { "xema.io/volume" = "templates-shared" })
  }
  spec {
    capacity                         = { storage = var.capacity }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = ""
    mount_options                    = var.mount_options
    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = var.nfs_export_path # IDENTICAL to the orchestrator PV — same bytes.
      }
    }
    claim_ref {
      namespace = var.workers_namespace
      name      = var.workers_pvc_name
    }
  }
}

resource "kubernetes_persistent_volume_claim" "orchestrator" {
  metadata {
    name      = var.orchestrator_pvc_name
    namespace = var.orchestrator_namespace
    labels    = var.labels
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume.orchestrator.metadata[0].name
    resources {
      requests = { storage = var.capacity }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "workers" {
  metadata {
    name      = var.workers_pvc_name
    namespace = var.workers_namespace
    labels    = var.labels
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume.workers.metadata[0].name
    resources {
      requests = { storage = var.capacity }
    }
  }
}
