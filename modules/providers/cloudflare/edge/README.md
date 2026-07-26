# `providers/cloudflare/edge`

Cloudflare zone settings that long-lived connections (SSE, WebSockets) depend
on. Narrow by design: it manages exactly the two toggles that decide whether a
streaming connection can survive the edge, and nothing about DNS records or
proxy status.

## Usage

```hcl
module "cloudflare_edge" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/cloudflare/edge?ref=v0.1.0"

  zone_id = "0eb7e5206e06bdce353779852b00c7b6" # xema.dev

  # Defaults; shown because they are the point of the module.
  websockets_enabled = true

  # Argo is a paid add-on and does not exist on this plan, so Terraform does not
  # manage it (the API answers 1015 for the setting). Flip to true only if the
  # zone is upgraded to a plan that includes Argo.
  manage_argo_smart_routing  = false
  argo_smart_routing_enabled = false
}
```

The provider is configured by the caller, as with every other module here:

```hcl
provider "cloudflare" {
  api_token = var.cloudflare_api_token # needs Zone Settings:Edit on the zone
}
```

## Why these two settings

The platform serves streaming traffic through this zone — three browser-facing
SSE endpoints (`agent-session-api` session events, `canopy-api` turns,
`activity-feed-api` realtime) and two WebSocket endpoints (`xema-shell-api`
`/shell/ws`, `biome-host-api` sandbox terminal).

- **`websockets`** must be `on` or the `Upgrade` handshake never reaches the
  origin. The failure is at the edge, so nothing appears in an origin log.
- **`argo_smart_routing`** must be `off`. Cloudflare documents Argo as
  [incompatible with WebSockets](https://developers.cloudflare.com/network/websockets/),
  so enabling it for latency would break every WebSocket session on the zone.
  On the current Free plan Argo is not available at all — the setting answers
  `1003 "Undefined zone setting"` (and `/zones/:id/argo/smart_routing` answers
  `1015 … Cause(s): smart_routing`) — so it
  cannot be switched on, and Terraform leaves it unmanaged by default
  (`manage_argo_smart_routing = false`). Managing it unconditionally would make
  `apply` fail on that 1015 rather than protect anything.

Before this module, both were dashboard-managed with no Terraform coverage: two
switches able to silently break every live session in the product, with no
review trail and no drift detection.

## What this module deliberately does not do

- **It does not set `proxy_read_timeout`.** That is the inter-byte limit which,
  once exceeded, produces a
  [524](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/)
  and truncates the response. It is Enterprise-only to configure, and `xema.dev`
  is on the Free plan, so the API rejects the write —
  `GET /zones/:id/settings/proxy_read_timeout` returns
  `{"value":"100","editable":false}`. Note the value: **100s on this zone**, not
  the 125s Cloudflare's connection-limits page quotes as the default. Budget
  against the zone, not the docs. The remedy lives in the application: a
  heartbeat, owned by
  `@xemahq/platform-common`'s `edge-stream` module and enforced in CI by
  `tooling/boundaries/check-stream-keepalive.mjs`. Raising the timeout would not
  remove the need for the heartbeat anyway, because Cloudflare also restarts edge
  servers on code releases and terminates connections.
- **It does not manage DNS records or proxy (orange-cloud) status.** That surface
  can move production traffic. Keeping it out means a change to this module
  cannot do so.

## Applying it

The zone is currently reconciled by hand, so the first `terraform apply` adopts
existing settings. Import them first to keep the plan a no-op:

```sh
terraform import 'module.cloudflare_edge.cloudflare_zone_setting.websockets' '<zone_id>/websockets'
```

Only `websockets` is imported: Argo is unmanaged by default (see above). If
`manage_argo_smart_routing` is ever turned on, import
`module.cloudflare_edge.cloudflare_zone_setting.argo_smart_routing[0]` too — note
the `[0]`, since the resource is created with `count`.

Then `terraform plan` and confirm it is empty before applying. An API token with
`Zone Settings:Edit` on the zone is required — a token limited to `Zone:Read`
can list zones but returns `Authentication error` on any zone-settings call.
