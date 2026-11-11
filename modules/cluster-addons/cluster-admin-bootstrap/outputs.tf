output "chart_version" {
  description = "The version read from the chart's Chart.yaml."
  value       = local.chart.version
}

output "apply_via" {
  description = "The mode this module applied the chart in."
  value       = var.apply_via
}
