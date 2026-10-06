# A ReadWriteMany NFS export shared across N namespaces.
#
# One namespace OWNS the tree (its workload writes it); any number of other
# namespaces MOUNT it (their workloads read it). PVCs are namespaced and a PV
# binds 1:1 to a single PVC, so one PVC cannot span namespaces. This module
# therefore creates one static PV + PVC pair PER NAMESPACE — one for the owner
# and one per consumer — every PV referencing the SAME NFS export (server +
# path). They all point at the same bytes, so what the owner writes is
# immediately visible in every consumer namespace.
#
# This is STATIC NFS binding (storageClassName = "") — distinct from the dynamic
# ReadWriteMany StorageClass in ../rwx-storage, where 1 PVC = 1 fresh volume
# that cannot be shared across namespaces. Every PV is pre-bound (claim_ref) so
# no PV can cross-bind to the wrong claim.

locals {
  pv_owner = "${var.name_prefix}-owner"
}

resource "kubernetes_persistent_volume_v1" "owner" {
  metadata {
    name   = local.pv_owner
    labels = var.labels
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
    claim_ref {
      namespace = var.owner_namespace
      name      = var.owner_pvc_name
    }
  }
}

resource "kubernetes_persistent_volume_v1" "consumer" {
  for_each = var.consumer_mounts

  metadata {
    name   = "${var.name_prefix}-consumer-${each.key}"
    labels = var.labels
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
        path   = var.nfs_export_path # IDENTICAL to the owner PV — same bytes.
      }
    }
    claim_ref {
      namespace = each.key
      name      = each.value
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "owner" {
  metadata {
    name      = var.owner_pvc_name
    namespace = var.owner_namespace
    labels    = var.labels
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume_v1.owner.metadata[0].name
    resources {
      requests = { storage = var.capacity }
    }
  }

  # Cross-input guard (a variable validation sees one variable only on 1.6):
  # the owner already holds its claim, so listing it as a consumer would plan a
  # second PV/PVC pair in the same namespace for the same export.
  lifecycle {
    precondition {
      condition     = !contains(keys(var.consumer_mounts), var.owner_namespace)
      error_message = "consumer_mounts must not contain owner_namespace (\"${var.owner_namespace}\"): the owner already holds its claim, owner_pvc_name."
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "consumer" {
  for_each = var.consumer_mounts

  metadata {
    name      = each.value
    namespace = each.key
    labels    = var.labels
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume_v1.consumer[each.key].metadata[0].name
    resources {
      requests = { storage = var.capacity }
    }
  }
}

moved {
  from = kubernetes_persistent_volume.owner
  to   = kubernetes_persistent_volume_v1.owner
}

moved {
  from = kubernetes_persistent_volume.consumer
  to   = kubernetes_persistent_volume_v1.consumer
}

moved {
  from = kubernetes_persistent_volume_claim.owner
  to   = kubernetes_persistent_volume_claim_v1.owner
}

moved {
  from = kubernetes_persistent_volume_claim.consumer
  to   = kubernetes_persistent_volume_claim_v1.consumer
}
