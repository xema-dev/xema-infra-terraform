variable "nfs_server" {
  description = "Host/IP of the NFS server backing the shared export (the same backend family as the cluster's ReadWriteMany StorageClass)."
  type        = string
}

variable "nfs_export_path" {
  description = "NFS export path dedicated to the shared tree. EVERY PersistentVolume this module creates references this identical path, so the owner and every consumer see the same bytes."
  type        = string
}

variable "owner_namespace" {
  description = "The namespace that OWNS the shared export — the one whose workload writes it. REQUIRED, no default: the module does not know who owns the tree."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.owner_namespace))
    error_message = "owner_namespace must be a DNS-1123 label."
  }
}

variable "owner_pvc_name" {
  description = "Name of the PersistentVolumeClaim created in owner_namespace. The owning workload mounts the export through this claim, so it must equal the claimName that workload references."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,251}[a-z0-9])?$", var.owner_pvc_name))
    error_message = "owner_pvc_name must be a DNS-1123 subdomain."
  }
}

variable "consumer_mounts" {
  description = <<-EOT
    The namespaces that MOUNT the shared export, keyed by namespace name, each
    value the PersistentVolumeClaim name to create there. One static
    PersistentVolume + PersistentVolumeClaim pair is created per entry, all
    referencing the same NFS export. REQUIRED, no default: which namespaces
    read the tree, and what each expects its claim to be called, is the
    consumer's own contract. The owner namespace may not appear here — it
    already has its claim (refused by a precondition, since a variable
    validation cannot see another variable on Terraform 1.6).
  EOT
  type        = map(string)

  validation {
    condition     = length(var.consumer_mounts) >= 1
    error_message = "consumer_mounts must name at least one namespace; a shared export nobody mounts is a plain volume."
  }

  validation {
    condition     = alltrue([for ns, pvc in var.consumer_mounts : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", ns)) && can(regex("^[a-z0-9]([a-z0-9-]{0,251}[a-z0-9])?$", pvc))])
    error_message = "Each consumer_mounts key must be a DNS-1123 label (a namespace) and each value a DNS-1123 subdomain (a claim name)."
  }
}

variable "name_prefix" {
  description = "Prefix for the static PersistentVolume names: `<prefix>-owner` and `<prefix>-consumer-<namespace>`. PVs are cluster-scoped, so the prefix must be unique per shared export on the cluster. REQUIRED, no default."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be a DNS-1123 label."
  }
}

variable "capacity" {
  description = "Requested capacity for the static PVs/PVCs (NFS ignores it for enforcement, but Kubernetes requires a value)."
  type        = string
  default     = "50Gi"
}

variable "mount_options" {
  description = "NFS mount options applied to every PV."
  type        = list(string)
  default     = ["nfsvers=4.1"]
}

variable "labels" {
  description = "Labels applied to every PV and PVC this module creates."
  type        = map(string)
  default = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/component"  = "shared-templates-volume"
  }
}
