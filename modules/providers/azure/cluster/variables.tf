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
      - zones      : availability zones to pin the pool to, each "1", "2" or
                     "3". Unset leaves the choice to Azure.
      - os_disk_size_gb : OS disk size in GB; unset keeps the VM size's default.
                     REQUIRED when os_disk_type is "Ephemeral" (the disk must fit the VM cache).
      - os_disk_type : "Managed" or "Ephemeral"; unset keeps the provider default (Managed).
      - taints     : node taints { key, value, effect } — NOT allowed on the
                     default pool (an AKS rule); put tainted pools elsewhere.
  EOT
  type = map(object({
    size            = string
    node_count      = number
    min_nodes       = optional(number)
    max_nodes       = optional(number)
    labels          = optional(map(string), {})
    zones           = optional(list(string))
    os_disk_size_gb = optional(number)
    os_disk_type    = optional(string)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  validation {
    condition     = alltrue([for p in values(var.node_pools) : p.os_disk_type == null ? true : contains(["Managed", "Ephemeral"], p.os_disk_type)])
    error_message = "Every node pool os_disk_type must be \"Managed\" or \"Ephemeral\"."
  }

  validation {
    condition     = alltrue([for p in values(var.node_pools) : p.os_disk_type == "Ephemeral" ? p.os_disk_size_gb != null : true])
    error_message = "A node pool with os_disk_type \"Ephemeral\" must set os_disk_size_gb (the disk must fit the VM cache)."
  }

  validation {
    condition     = alltrue([for p in values(var.node_pools) : p.zones == null ? true : alltrue([for z in p.zones : contains(["1", "2", "3"], z)])])
    error_message = "Every node pool zones entry must be \"1\", \"2\" or \"3\"."
  }

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
  description = "Existing resource group to create the cluster in. Empty string creates a dedicated resource group named \"<name>-rg\"."
  type        = string
  default     = ""
}

variable "vnet_id" {
  description = "Virtual network the cluster's nodes live in (providers/azure/network's vnet_id). The cluster identity is granted Network Contributor on it."
  type        = string
}

variable "node_subnet_id" {
  description = "Subnet the node pools are placed in (providers/azure/network's aks_subnet_id)."
  type        = string
}

variable "service_cidr" {
  description = "Kubernetes Service CIDR. Must not overlap the VNet address space."
  type        = string
  default     = "10.100.0.0/16"
  nullable    = false
}

variable "dns_service_ip" {
  description = "Cluster DNS service IP (inside service_cidr)."
  type        = string
  default     = "10.100.0.10"
  nullable    = false
}

variable "pod_cidr" {
  description = "Pod CIDR for Azure CNI overlay. Must not overlap the VNet address space or service_cidr."
  type        = string
  default     = "10.244.0.0/16"
  nullable    = false
}

variable "network_policy_engine" {
  description = <<-EOT
    The NetworkPolicy engine enforcing every Kubernetes NetworkPolicy on the cluster (Azure CNI overlay):
      - "cilium" (default): Azure CNI Powered by Cilium (network_data_plane = "cilium")
      - "calico"          : Calico (Azure dataplane)
    There is deliberately no "none": a cluster without a policy engine ignores NetworkPolicies silently, so it is
    unrepresentable. Changing this on an EXISTING cluster changes its network dataplane and forces cluster recreation.
  EOT
  type        = string
  default     = "cilium"
  nullable    = false
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

variable "outbound_type" {
  description = "AKS egress: \"loadBalancer\" (default — AKS provisions its own public egress address), \"userDefinedRouting\" (no AKS-managed egress; the node subnet's existing route table decides, e.g. 0.0.0.0/0 to a firewall — requires route_table_id), \"managedNATGateway\" or \"userAssignedNATGateway\"."
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.outbound_type)
    error_message = "outbound_type must be one of loadBalancer, userDefinedRouting, managedNATGateway, userAssignedNATGateway."
  }
}

variable "route_table_id" {
  description = "Id of the route table associated with node_subnet_id. Required with outbound_type = \"userDefinedRouting\"; the cluster identity is granted Network Contributor on it. The route table is never managed by this module."
  type        = string
  default     = ""
}

variable "private_cluster_enabled" {
  description = "Expose the Kubernetes API only on a private address inside the VNet (no public endpoint). Default false."
  type        = bool
  default     = false
}

variable "private_cluster_public_fqdn_enabled" {
  description = "For a private cluster: also publish the API's PRIVATE address under a public DNS name, so clients on a VNet with custom DNS resolve it without access to the Azure private zone. The endpoint stays private. Ignored when private_cluster_enabled = false."
  type        = bool
  default     = false
}

variable "entra_rbac" {
  description = <<-EOT
    Microsoft Entra ID authentication with Azure RBAC for Kubernetes authorization.
    null (default) keeps AKS's certificate-based local accounts as the only access.
      - tenant_id              : Entra tenant; "" uses the subscription's tenant
      - admin_group_object_ids : Entra groups granted cluster-admin
      - local_account_disabled : true turns certificate (local) accounts OFF, so
                                 every caller must authenticate through Entra ID
  EOT
  type = object({
    tenant_id              = optional(string, "")
    admin_group_object_ids = optional(list(string), [])
    local_account_disabled = optional(bool, true)
  })
  default = null
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
