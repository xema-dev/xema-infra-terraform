# Pure rules (no provider, no resources): the version, channel and maintenance-window settings of
# an AKS cluster. Kept apart from providers/azure/cluster so they are testable without a provider
# on Terraform 1.6 and OpenTofu. Every setting left null means Azure's own default.

locals {
  windows = {
    auto_upgrade = var.maintenance_window_auto_upgrade
    node_os      = var.maintenance_window_node_os
  }

  # Messages per window; empty when the window is unset or well formed.
  window_errors = {
    for name, w in local.windows : name => w == null ? [] : concat(
      contains(["Daily", "Weekly", "AbsoluteMonthly", "RelativeMonthly"], w.frequency) ? [] : ["maintenance_window_${name}.frequency must be one of Daily, Weekly, AbsoluteMonthly, RelativeMonthly."],
      w.interval >= 1 ? [] : ["maintenance_window_${name}.interval must be at least 1."],
      w.duration >= 4 && w.duration <= 24 ? [] : ["maintenance_window_${name}.duration must be 4 to 24 hours."],
      contains(["Weekly", "RelativeMonthly"], w.frequency) && w.day_of_week == null ? ["maintenance_window_${name}.day_of_week is required for Weekly and RelativeMonthly."] : [],
      w.frequency == "AbsoluteMonthly" && w.day_of_month == null ? ["maintenance_window_${name}.day_of_month is required for AbsoluteMonthly."] : [],
      w.frequency == "RelativeMonthly" && w.week_index == null ? ["maintenance_window_${name}.week_index is required for RelativeMonthly."] : [],
    )
  }
}

output "kubernetes_version" {
  description = "azurerm_kubernetes_cluster.kubernetes_version."
  value       = var.kubernetes_version
}

output "automatic_upgrade_channel" {
  description = "azurerm_kubernetes_cluster.automatic_upgrade_channel (null: Azure's default)."
  value       = var.automatic_upgrade_channel
}

output "node_os_upgrade_channel" {
  description = "azurerm_kubernetes_cluster.node_os_upgrade_channel (null: Azure's default)."
  value       = var.node_os_upgrade_channel
}

# Lists of zero or one, to drive a dynamic block. Evaluating them is what enforces the window rules.
output "maintenance_window_auto_upgrade" {
  description = "Zero or one maintenance_window_auto_upgrade block."
  value       = local.windows.auto_upgrade == null ? [] : [local.windows.auto_upgrade]

  precondition {
    condition     = length(local.window_errors.auto_upgrade) == 0
    error_message = join(" ", local.window_errors.auto_upgrade)
  }
}

output "maintenance_window_node_os" {
  description = "Zero or one maintenance_window_node_os block."
  value       = local.windows.node_os == null ? [] : [local.windows.node_os]

  precondition {
    condition     = length(local.window_errors.node_os) == 0
    error_message = join(" ", local.window_errors.node_os)
  }
}
