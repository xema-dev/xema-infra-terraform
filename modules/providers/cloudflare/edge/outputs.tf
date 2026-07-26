output "websockets_enabled" {
  description = "Effective WebSocket proxying state for the zone."
  value       = var.websockets_enabled
}

output "argo_smart_routing_enabled" {
  description = <<-EOT
    Effective Argo Smart Routing state. Expected false — Cloudflare documents
    Argo as incompatible with WebSockets.
  EOT
  value       = var.argo_smart_routing_enabled
}
