variable "engine" {
  description = <<-EOT
    The NetworkPolicy engine enforcing every Kubernetes NetworkPolicy on an AKS cluster (Azure CNI overlay):
      - "cilium" (default): Azure CNI Powered by Cilium
      - "azure"           : Azure Network Policy Manager
      - "calico"          : Calico
    There is deliberately no "none": a cluster without a policy engine silently ignores every NetworkPolicy.
  EOT
  type        = string
  default     = "cilium"
  nullable    = false

  validation {
    condition     = contains(["cilium", "azure", "calico"], var.engine)
    error_message = "network_policy_engine must be one of cilium, azure, calico. There is no \"none\": a cluster without a NetworkPolicy engine silently ignores every NetworkPolicy. (The module always uses Azure CNI overlay, which all three support; kubenet is not supported.)"
  }
}
