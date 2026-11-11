variable "aks_cluster_id" {
  type        = string
  description = "Resource id of the private AKS cluster."
}

variable "kube_host" {
  type        = string
  description = "API server URL; only used with apply_via = in-vnet."
  default     = null
}

variable "kube_ca_b64" {
  type        = string
  description = "Base64 cluster CA; only used with apply_via = in-vnet."
  default     = null
}
