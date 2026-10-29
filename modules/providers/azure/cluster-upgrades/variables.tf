variable "kubernetes_version" {
  description = "AKS control-plane version: a minor alias (\"1.31\") or a full version (\"1.31.5\")."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor alias like \"1.31\" or a full version like \"1.31.5\"."
  }
}

variable "automatic_upgrade_channel" {
  description = "AKS automatic upgrade channel, or null to leave it to Azure (no automatic upgrade)."
  type        = string
  default     = null

  validation {
    condition     = var.automatic_upgrade_channel == null ? true : contains(["patch", "rapid", "stable", "node-image", "none"], var.automatic_upgrade_channel)
    error_message = "automatic_upgrade_channel must be null or one of patch, rapid, stable, node-image, none."
  }
}

variable "node_os_upgrade_channel" {
  description = "AKS node OS upgrade channel, or null for Azure's own default (NodeImage)."
  type        = string
  default     = null

  validation {
    condition     = var.node_os_upgrade_channel == null ? true : contains(["NodeImage", "SecurityPatch", "Unmanaged", "None"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be null or one of NodeImage, SecurityPatch, Unmanaged, None."
  }
}

variable "maintenance_window_auto_upgrade" {
  description = "Maintenance window of the automatic cluster upgrades (providers/azure/cluster's input of the same name), or null for none."
  type = object({
    frequency    = string
    interval     = number
    duration     = number
    day_of_week  = optional(string)
    day_of_month = optional(number)
    week_index   = optional(string)
    start_time   = optional(string)
    utc_offset   = optional(string)
    start_date   = optional(string)
    not_allowed = optional(list(object({
      start = string
      end   = string
    })), [])
  })
  default = null
}

variable "maintenance_window_node_os" {
  description = "Maintenance window of the node OS upgrades (providers/azure/cluster's input of the same name), or null for none."
  type = object({
    frequency    = string
    interval     = number
    duration     = number
    day_of_week  = optional(string)
    day_of_month = optional(number)
    week_index   = optional(string)
    start_time   = optional(string)
    utc_offset   = optional(string)
    start_date   = optional(string)
    not_allowed = optional(list(object({
      start = string
      end   = string
    })), [])
  })
  default = null
}
