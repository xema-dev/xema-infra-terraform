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

  # Both are the defaults; shown here because they are the point of the module.
  websockets_enabled         = true
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

Before this module, both were dashboard-managed with no Terraform coverage: two
switches able to silently break every live session in the product, with no
review trail and no drift detection.

## What this module deliberately does not do

- **It does not set `proxy_read_timeout`.** That limit (125s between bytes,
  then [524](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/))
  is Enterprise-only to configure, and `xema.dev` is on the Free plan — the API
  rejects the write. The remedy lives in the application: a heartbeat, owned by
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
terraform import 'module.cloudflare_edge.cloudflare_zone_setting.websockets'         '<zone_id>/websockets'
terraform import 'module.cloudflare_edge.cloudflare_zone_setting.argo_smart_routing' '<zone_id>/argo_smart_routing'
```

Then `terraform plan` and confirm it is empty before applying. An API token with
`Zone Settings:Edit` on the zone is required — a token limited to `Zone:Read`
can list zones but returns `Authentication error` on any zone-settings call.
