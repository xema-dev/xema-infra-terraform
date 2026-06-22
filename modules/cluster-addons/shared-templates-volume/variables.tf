variable "nfs_server" {
  description = "Host/IP of the RWX NFS server backing the shared templates export (same backend family as the nfs-rwx StorageClass)."
  type        = string
}

variable "nfs_export_path" {
  description = "NFS export path dedicated to the shared templates tree. BOTH PVs reference this identical path so the orchestrator and workers see the same bytes."
  type        = string
}

variable "orchestrator_namespace" {
  description = "Namespace the workspace-orchestrator runs in (mounts the volume RW at TEMPLATES_POOL_ROOT_PATH)."
  type        = string
  default     = "xema-prod"
}

variable "workers_namespace" {
  description = "Namespace session worker pods run in (mount the volume RO via subPath)."
  type        = string
  default     = "xema-opencode-workers"
}

variable "orchestrator_pvc_name" {
  description = "PVC name claimed by the orchestrator. Must match the claimName in the orchestrator helm values (xema-templates-shared)."
  type        = string
  default     = "xema-templates-shared"
}

variable "workers_pvc_name" {
  description = "PVC name claimed by workers. CONTRACT-BOUND: must equal `xema-pool-<SHARED_TEMPLATES_POOL_SLUG>` so the storage driver's derived claim name resolves."
  type        = string
  default     = "xema-pool-templates-shared"
}

variable "capacity" {
  description = "Requested capacity for the static PVs/PVCs (NFS ignores it for enforcement, but K8s requires a value)."
  type        = string
  default     = "50Gi"
}

variable "mount_options" {
  description = "NFS mount options applied to both PVs."
  type        = list(string)
  default     = ["nfsvers=4.1"]
}

variable "labels" {
  description = "Labels applied to the PVs/PVCs."
  type        = map(string)
  default = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/component"  = "shared-templates-volume"
  }
}
