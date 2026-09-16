variable "zone_id" {
  description = "Cloudflare zone id for the managed apex (e.g. the zone for \"example.com\")."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hex Cloudflare zone id."
  }
}

variable "websocket_paths" {
  description = <<-EOT
    The origin paths served through this zone that carry WebSocket traffic
    (e.g. ["/shell/ws", "/terminal"]). REQUIRED, no default: which paths need
    an `Upgrade` handshake to reach the origin is a fact about what the
    consumer serves, and the module does not know it. It is the module's
    evidence for the `websockets` setting: while this set is non-empty, a plan
    that would turn WebSocket proxying off is REFUSED, because with it off the
    handshake never reaches the origin and every listed path fails closed at
    the edge with nothing in an origin log to explain it. Pass [] to declare
    that nothing on the zone needs WebSockets. Each path starts with "/".
  EOT
  type        = set(string)

  validation {
    condition     = alltrue([for p in var.websocket_paths : startswith(p, "/")])
    error_message = "Each websocket_paths entry must be an origin path starting with \"/\"."
  }
}

variable "websockets_enabled" {
  description = <<-EOT
    Whether the zone proxies WebSocket connections.

    Refused off while websocket_paths is non-empty (see that input). Declared
    rather than left at Cloudflare's default so the dependency is explicit and
    drift is caught rather than discovered.
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
    Declaring the resource anyway would make `terraform apply` fail rather
    than protect anything. On a Free-plan zone Argo cannot be enabled and so
    cannot break WebSockets.

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
