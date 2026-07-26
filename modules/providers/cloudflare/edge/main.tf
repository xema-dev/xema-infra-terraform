# ─────────────────────────────────────────────────────────────────────────────
# Cloudflare edge settings that long-lived connections depend on.
#
# The platform serves three browser-facing SSE endpoints and two WebSocket
# endpoints through this zone. Two documented edge limits bound them, and NEITHER
# is configurable below the Enterprise plan:
#
#   • Proxy Read Timeout — 125s between bytes of an origin response, then 524
#     and the response is truncated mid-stream.
#   • WebSocket idle timeout — the edge closes a socket carrying no data in
#     either direction (~100s observed; Cloudflare does not publish the figure).
#
# So the application-side remedy is a heartbeat, owned by
# `@xemahq/platform-common`'s `edge-stream` module and enforced by
# `tooling/boundaries/check-stream-keepalive.mjs`. THIS module covers the part
# that cannot live in application code: the two zone toggles that decide whether
# a long-lived connection is possible at all.
#
# Why it exists as code: these settings were dashboard-managed, with zero
# Terraform coverage anywhere in this repo. That means the two switches that can
# silently break every WebSocket session in the product had no review trail, no
# drift detection, and no record of intent. A toggle nobody can see is a toggle
# nobody can rule out during an incident.
#
# Deliberately NOT declared here:
#   • `proxy_read_timeout` — Enterprise-only. Setting it on a lower plan is an
#     API error, and `xema.dev` is on the Free plan. The heartbeat is the fix.
#   • Anything touching DNS records or proxy (orange-cloud) status. Those are a
#     larger surface with real blast radius, and folding them into a module about
#     connection liveness would make an innocuous-looking change able to move
#     traffic.
# ─────────────────────────────────────────────────────────────────────────────

# WebSocket proxying. Cloudflare's default is on for all plans; declared so the
# dependency is explicit and drift is caught rather than discovered.
resource "cloudflare_zone_setting" "websockets" {
  zone_id    = var.zone_id
  setting_id = "websockets"
  value      = var.websockets_enabled ? "on" : "off"
}

# Argo Smart Routing. Cloudflare documents it as incompatible with WebSockets,
# so this pins it off rather than trusting that nobody enables it for latency.
resource "cloudflare_zone_setting" "argo_smart_routing" {
  zone_id    = var.zone_id
  setting_id = "argo_smart_routing"
  value      = var.argo_smart_routing_enabled ? "on" : "off"
}
