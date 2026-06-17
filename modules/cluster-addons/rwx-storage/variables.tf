variable "chart_repository" {
  description = "Helm repository URL for the NFS provisioner chart. Swap to e.g. \"https://kubernetes-sigs.github.io/csi-driver-nfs\" to adopt a different provisioner."
  type        = string
  default     = "https://openebs.github.io/dynamic-nfs-provisioner"
}

variable "chart_name" {
  description = "Helm chart name for the NFS provisioner (e.g. \"nfs-provisioner\" or \"csi-driver-nfs\")."
  type        = string
  default     = "nfs-provisioner"
}

variable "chart_version" {
  description = "Pinned Helm chart version. Empty string installs the latest available version from the repository."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace the NFS provisioner Helm release is installed into."
  type        = string
  default     = "openebs"
}

variable "create_namespace" {
  description = "Whether the Helm release should create its target namespace if it does not already exist."
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Helm release name for the NFS provisioner."
  type        = string
  default     = "openebs-nfs-provisioner"
}

variable "chart_values" {
  description = "Inline Helm values for the provisioner chart, merged on top of chart defaults. Each entry is a YAML document string (same shape Helm expects)."
  type        = list(string)
  default     = []
}

variable "chart_set" {
  description = "Scalar Helm --set overrides for the provisioner chart, keyed by value path (e.g. { \"replicaCount\" = \"1\" })."
  type        = map(string)
  default     = {}
}

variable "storage_class_name" {
  description = "Name of the ReadWriteMany StorageClass to create. Must match the name the Helm app bring-up references."
  type        = string
  default     = "nfs-rwx-storage"
}

variable "storage_class_provisioner" {
  description = "The provisioner field on the StorageClass. Must match the provisioner the installed chart registers (e.g. \"openebs.io/nfsrwx\" for dynamic-nfs-provisioner, \"nfs.csi.k8s.io\" for csi-driver-nfs)."
  type        = string
  default     = "openebs.io/nfsrwx"
}

variable "storage_class_parameters" {
  description = "Parameters passed to the StorageClass provisioner (provisioner-specific, e.g. the backing StorageClass / NFS server reference)."
  type        = map(string)
  default     = {}
}

variable "volume_binding_mode" {
  description = "StorageClass volumeBindingMode. One of \"Immediate\" or \"WaitForFirstConsumer\"."
  type        = string
  default     = "Immediate"

  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.volume_binding_mode)
    error_message = "volume_binding_mode must be one of Immediate, WaitForFirstConsumer."
  }
}

variable "reclaim_policy" {
  description = "StorageClass reclaimPolicy. One of \"Delete\" or \"Retain\"."
  type        = string
  default     = "Delete"

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be one of Delete, Retain."
  }
}

variable "allow_volume_expansion" {
  description = "Whether PVCs bound to this StorageClass may be expanded."
  type        = bool
  default     = true
}

variable "is_default_class" {
  description = "Mark this StorageClass as the cluster default (sets the storageclass.kubernetes.io/is-default-class annotation)."
  type        = bool
  default     = false
}

variable "storage_class_labels" {
  description = "Labels applied to the StorageClass metadata."
  type        = map(string)
  default     = {}
}
