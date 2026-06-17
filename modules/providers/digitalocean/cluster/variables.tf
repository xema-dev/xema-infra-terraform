variable "name" {
  description = "Cluster name."
  type        = string
}

variable "region" {
  description = "DigitalOcean region slug (e.g. \"fra1\")."
  type        = string
}

variable "kubernetes_version" {
  description = "DOKS control-plane version slug prefix (e.g. \"1.31.\"). Resolved to the latest matching patch."
  type        = string
}

variable "node_pools" {
  description = <<-EOT
    Node pools keyed by a stable pool id (e.g. "generic", "workers"). The first
    pool in iteration order becomes the DOKS default pool; the rest are attached
    as additional pools. Each pool:
      - size       : DO droplet slug (e.g. "s-4vcpu-8gb")
      - node_count : fixed node count when autoscaling is off
      - min_nodes  : enable autoscaling when set (with max_nodes)
      - max_nodes  : autoscaling upper bound
      - labels     : kubernetes node labels
      - taints     : node taints { key, value, effect }
  EOT
  type = map(object({
    size       = string
    node_count = number
    min_nodes  = optional(number)
    max_nodes  = optional(number)
    labels     = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  validation {
    condition     = length(var.node_pools) >= 1
    error_message = "At least one node pool is required."
  }

  validation {
    condition = alltrue([
      for p in values(var.node_pools) : alltrue([
        for t in p.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)
      ])
    ])
    error_message = "Taint effect must be one of NoSchedule, PreferNoSchedule, NoExecute."
  }
}

variable "default_pool_id" {
  description = "Which key in node_pools is the DOKS default pool. Must exist in node_pools."
  type        = string

  validation {
    condition     = length(var.default_pool_id) > 0
    error_message = "default_pool_id must be set to one of the node_pools keys."
  }
}

variable "vpc_id" {
  description = "Existing VPC uuid to place the cluster in. Empty string lets DO pick the region default VPC."
  type        = string
  default     = ""
}

variable "auto_upgrade" {
  description = "Enable DOKS patch auto-upgrade."
  type        = bool
  default     = false
}

variable "surge_upgrade" {
  description = "Enable DOKS surge upgrades."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the cluster."
  type        = map(string)
  default     = {}
}
