variable "name" {
  description = "Cluster name. Also used as the AKS dns_prefix and, when no resource group is supplied, as the stem of the created resource group (\"<name>-rg\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "name must be 2-63 chars of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Azure location (e.g. \"westeurope\")."
  type        = string
}

variable "kubernetes_version" {
  description = "AKS control-plane version prefix (e.g. \"1.31\"). Resolved to the latest matching patch available in the region."
  type        = string
}

variable "node_pools" {
  description = <<-EOT
    Node pools keyed by a stable pool id. The key is ALSO the AKS agent pool
    name, so it must match ^[a-z][a-z0-9]{0,11}$. The pool named by
    default_pool_id becomes the AKS default (system) pool; the rest are attached
    as additional user pools. Each pool:
      - size       : Azure VM size (e.g. "Standard_D4s_v5")
      - node_count : fixed node count when autoscaling is off
      - min_nodes  : enable autoscaling when set (with max_nodes)
      - max_nodes  : autoscaling upper bound
      - labels     : kubernetes node labels
      - taints     : node taints { key, value, effect } — NOT allowed on the
                     default pool (an AKS rule); put tainted pools elsewhere.
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
    condition     = alltrue([for k in keys(var.node_pools) : can(regex("^[a-z][a-z0-9]{0,11}$", k))])
    error_message = "Every node_pools key is an AKS agent pool name and must match ^[a-z][a-z0-9]{0,11}$."
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
  description = "Which key in node_pools is the AKS default (system) pool. Must exist in node_pools and must declare no taints."
  type        = string

  validation {
    condition     = length(var.default_pool_id) > 0
    error_message = "default_pool_id must be set to one of the node_pools keys."
  }
}

variable "resource_group_name" {
  description = "Existing resource group to create the cluster and its network in. Empty string creates a dedicated resource group named \"<name>-rg\"."
  type        = string
  default     = ""
}

variable "vnet_address_space" {
  description = "Address space of the virtual network the module creates."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_prefix" {
  description = "Address prefix of the AKS node subnet (inside vnet_address_space)."
  type        = string
  default     = "10.0.0.0/20"
}

variable "postgres_subnet_prefix" {
  description = "Address prefix of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers (inside vnet_address_space). Consumed by providers/azure/managed-postgres via the delegated_subnet_id output."
  type        = string
  default     = "10.0.16.0/24"
}

variable "service_cidr" {
  description = "Kubernetes Service CIDR. Must not overlap vnet_address_space."
  type        = string
  default     = "10.100.0.0/16"
}

variable "dns_service_ip" {
  description = "Cluster DNS service IP (inside service_cidr)."
  type        = string
  default     = "10.100.0.10"
}

variable "pod_cidr" {
  description = "Pod CIDR for Azure CNI overlay. Must not overlap vnet_address_space or service_cidr."
  type        = string
  default     = "10.244.0.0/16"
}

variable "sku_tier" {
  description = "AKS control-plane SKU tier: one of \"Free\", \"Standard\", \"Premium\"."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be one of Free, Standard, Premium."
  }
}

variable "automatic_upgrade_channel" {
  description = "AKS automatic upgrade channel: one of \"patch\", \"rapid\", \"node-image\", \"stable\", or \"\" (empty) to leave automatic upgrades OFF, which is the default — mirroring the DigitalOcean module's auto_upgrade = false."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "patch", "rapid", "node-image", "stable"], var.automatic_upgrade_channel)
    error_message = "automatic_upgrade_channel must be one of patch, rapid, node-image, stable, or empty."
  }
}

variable "authorized_ip_ranges" {
  description = "CIDRs allowed to reach the Kubernetes API server. Empty (default) leaves the public endpoint unrestricted."
  type        = list(string)
  default     = []
}

variable "enable_log_analytics" {
  description = "Create a Log Analytics workspace and wire the AKS monitoring (oms_agent) add-on to it."
  type        = bool
  default     = false
}

variable "log_analytics_retention_days" {
  description = "Log Analytics retention in days (used only when enable_log_analytics)."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every created resource."
  type        = map(string)
  default     = {}
}
