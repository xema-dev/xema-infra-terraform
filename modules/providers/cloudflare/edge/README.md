# `providers/cloudflare/edge`

Cloudflare zone settings that long-lived connections (SSE, WebSockets) depend
on. Narrow by design: it manages exactly the two toggles that decide whether a
streaming connection can survive the edge, and nothing about DNS records or
proxy status.

The module deals in the capability — *this zone proxies WebSockets, and Argo
is pinned off* — and knows nothing about which application serves them. The
consumer declares the paths that need WebSocket proxying (`websocket_paths`),
and that declaration is what the module holds the setting on.

## Usage

```hcl
module "cloudflare_edge" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/cloudflare/edge?ref=v1.0.0"

  zone_id = "0123456789abcdef0123456789abcdef" # EXAMPLE zone id

  # EXAMPLE paths — the origin paths YOUR services serve WebSockets on. While
  # this set is non-empty, a plan that turns WebSocket proxying off is refused.
  websocket_paths = ["/shell/ws", "/terminal"]

  # Defaults; shown because they are the point of the module.
  websockets_enabled = true

  # Argo is a paid add-on and does not exist on a Free-plan zone, so Terraform
  # does not manage it (the API answers 1015 for the setting). Flip to true only
  # if the zone is upgraded to a plan that includes Argo.
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

- **`websockets`** must be `on` or the `Upgrade` handshake never reaches the
  origin. The failure is at the edge, so nothing appears in an origin log. The
  module refuses to plan it off while `websocket_paths` is non-empty — the
  consumer removes the paths first if they are genuinely gone.
- **`argo_smart_routing`** must be `off`. Cloudflare documents Argo as
  [incompatible with WebSockets](https://developers.cloudflare.com/network/websockets/),
  so enabling it for latency would break every WebSocket session on the zone.
  On a Free-plan zone Argo is not available at all — the setting answers
  `1003 "Undefined zone setting"` (and `/zones/:id/argo/smart_routing` answers
  `1015 … Cause(s): smart_routing`) — so it cannot be switched on, and Terraform
  leaves it unmanaged by default (`manage_argo_smart_routing = false`).
  Managing it unconditionally would make `apply` fail on that 1015 rather than
  protect anything.

Before this module, both were dashboard-managed with no Terraform coverage: two
switches able to silently break every live session on the zone, with no review
trail and no drift detection.

## What this module deliberately does not do

- **It does not set `proxy_read_timeout`.** That is the inter-byte limit which,
  once exceeded, produces a
  [524](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/)
  and truncates the response. It is Enterprise-only to configure; on a lower
  plan the API rejects the write — `GET /zones/:id/settings/proxy_read_timeout`
  returns `{"value":"100","editable":false}`. Note the value: **100s on a
  Free-plan zone**, not the 125s Cloudflare's connection-limits page quotes as
  the default. Budget against the zone, not the docs. The remedy lives in the
  application — a heartbeat on every long-lived response — and raising the
  timeout would not remove the need for it anyway, because Cloudflare also
  restarts edge servers on code releases and terminates connections.
- **It does not manage DNS records or proxy (orange-cloud) status.** That surface
  can move production traffic. Keeping it out means a change to this module
  cannot do so.

## Inputs and outputs

| Input | Required | Description |
| --- | --- | --- |
| `zone_id` | **yes** | the Cloudflare zone id (32 hex chars) |
| `websocket_paths` | **yes** | the origin paths that carry WebSocket traffic (each starts with `/`); `[]` declares none |
| `websockets_enabled` | no | proxy WebSockets (`true`); refused `false` while `websocket_paths` is non-empty |
| `manage_argo_smart_routing` | no | manage the Argo setting at all (`false`) |
| `argo_smart_routing_enabled` | no | Argo state when managed (`false`; must stay so) |

Outputs: `websockets_enabled`, `websocket_paths`, `argo_smart_routing_managed`.

## Applying it

On a zone reconciled by hand, the first `terraform apply` adopts the existing
setting. Import it first to keep the plan a no-op:

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
