output "websockets_enabled" {
  description = "Effective WebSocket proxying state for the zone."
  value       = var.websockets_enabled
}

output "argo_smart_routing_managed" {
  description = <<-EOT
    Whether Terraform manages Argo Smart Routing on this zone. False on a plan
    without the Argo add-on, where the setting does not exist — and therefore
    cannot be switched on to break WebSockets.
  EOT
  value       = var.manage_argo_smart_routing
}

output "websocket_paths" {
  description = "The origin paths the consumer declared as WebSocket-carrying — the evidence the websockets setting is held on for."
  value       = var.websocket_paths
}
