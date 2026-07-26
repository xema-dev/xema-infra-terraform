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

variable "manage_argo_smart_routing" {
  description = <<-EOT
    Whether Terraform manages the Argo Smart Routing setting at all.

    Default false: Argo is a paid add-on, and on a plan without it the setting
    does not exist — the settings API answers 1003 "Undefined zone setting"
    (and the dedicated Argo endpoint 1015 "not authorized … smart_routing").
    Declaring the resource anyway would make
    `terraform apply` fail rather than protect anything. `xema.dev` is on the
    Free plan, so Argo cannot be enabled there and cannot break WebSockets.

    Flip to true if the zone is upgraded to a plan that includes Argo — that is
    when pinning it off begins to matter.
  EOT
  type        = bool
  default     = false
}

variable "argo_smart_routing_enabled" {
  description = <<-EOT
    Whether Argo Smart Routing is enabled.

    MUST stay false. Cloudflare documents Argo as INCOMPATIBLE with WebSockets
    (see https://developers.cloudflare.com/network/websockets/ "Compatibility
    notes"), so enabling it would break every WebSocket session on the zone.

    Only takes effect when `manage_argo_smart_routing` is true; see that
    variable for why managing it is opt-in.
  EOT
  type        = bool
  default     = false
}
