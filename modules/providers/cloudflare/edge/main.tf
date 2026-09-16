# ─────────────────────────────────────────────────────────────────────────────
# Cloudflare edge settings that long-lived connections depend on.
#
# A consumer serving streaming traffic (SSE, WebSockets) through this zone is
# bounded by two documented edge limits, and NEITHER is configurable below the
# Enterprise plan:
#
#   • Proxy Read Timeout — 100s between bytes of an origin response, then 524
#     and the response is truncated mid-stream. (Read it from the zone; the
#     docs quote 125s as the default, a Free-plan zone reports `"value":"100"`.)
#   • WebSocket idle timeout — the edge closes a socket carrying no data in
#     either direction (~100s observed; Cloudflare does not publish the figure).
#
# So the application-side remedy is a heartbeat, and it belongs to the
# application. THIS module covers the part that cannot live in application
# code: the zone toggles that decide whether a long-lived connection is
# possible at all.
#
# Why it exists as code: these settings are otherwise dashboard-managed, with
# no Terraform coverage. That means the two switches that can silently break
# every WebSocket session on the zone have no review trail, no drift
# detection, and no record of intent. A toggle nobody can see is a toggle
# nobody can rule out during an incident.
#
# Deliberately NOT declared here:
#   • `proxy_read_timeout` — Enterprise-only. Setting it on a lower plan is an
#     API error. The heartbeat is the fix.
#   • Anything touching DNS records or proxy (orange-cloud) status. Those are a
#     larger surface with real blast radius, and folding them into a module about
#     connection liveness would make an innocuous-looking change able to move
#     traffic.
# ─────────────────────────────────────────────────────────────────────────────

# WebSocket proxying. Cloudflare's default is on for all plans; declared so the
# dependency is explicit and drift is caught rather than discovered. The
# consumer states WHICH paths depend on it (var.websocket_paths), and that
# declaration is what refuses a plan that would switch it off under them.
resource "cloudflare_zone_setting" "websockets" {
  zone_id    = var.zone_id
  setting_id = "websockets"
  value      = var.websockets_enabled ? "on" : "off"

  lifecycle {
    precondition {
      condition     = var.websockets_enabled || length(var.websocket_paths) == 0
      error_message = "websockets_enabled = false while websocket_paths declares ${length(var.websocket_paths)} path(s) that need WebSocket proxying: ${join(", ", sort(tolist(var.websocket_paths)))}. Turning the setting off would fail every one of them closed at the edge. Remove the paths first if they are genuinely gone."
    }
  }
}

# Argo Smart Routing. Cloudflare documents it as incompatible with WebSockets,
# so the intent is to pin it OFF rather than trust that nobody enables it for
# latency.
#
# Not managed by default, because Argo is a PAID ADD-ON and the setting does not
# exist on a plan without it. Verified against a Free-plan zone:
#   GET /zones/:id/settings/argo_smart_routing
#     → 1003 "Undefined zone setting: argo_smart_routing"
#   GET /zones/:id/argo/smart_routing
#     → 1015 "The request is not authorized to access this setting.
#             Cause(s): smart_routing"
#   GET /zones/:id/argo → 7000 "No route for that URI"
# So on such a plan Argo cannot be enabled at all and therefore cannot break
# WebSockets — and unconditionally declaring the resource would make
# `terraform apply` FAIL on that 1015 rather than protect anything.
#
# Set `manage_argo_smart_routing = true` if the zone is ever upgraded to a plan
# that includes Argo; that is exactly when pinning it off starts to matter.
resource "cloudflare_zone_setting" "argo_smart_routing" {
  count = var.manage_argo_smart_routing ? 1 : 0

  zone_id    = var.zone_id
  setting_id = "argo_smart_routing"
  value      = var.argo_smart_routing_enabled ? "on" : "off"
}
