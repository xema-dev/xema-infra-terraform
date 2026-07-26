variable "zone_id" {
  description = "Cloudflare zone id for the managed apex (e.g. the zone for \"xema.dev\")."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hex Cloudflare zone id."
  }
}

variable "websockets_enabled" {
  description = <<-EOT
    Whether the zone proxies WebSocket connections.

    MUST stay true. The platform serves WebSockets through the edge —
    xema-shell-api's `/shell/ws` and biome-host-api's sandbox terminal. With this
    off, the `Upgrade` handshake never reaches the origin and both features fail
    closed at the edge, with nothing in an origin log to explain it.
  EOT
  type        = bool
  default     = true
}

variable "argo_smart_routing_enabled" {
  description = <<-EOT
    Whether Argo Smart Routing is enabled.

    MUST stay false. Cloudflare documents Argo as INCOMPATIBLE with WebSockets
    (see https://developers.cloudflare.com/network/websockets/ "Compatibility
    notes"), so enabling it would break every WebSocket session on the zone.

    Declared here — rather than simply left alone — so that turning it on is a
    visible, reviewed diff instead of a dashboard click nobody can see.
  EOT
  type        = bool
  default     = false
}
