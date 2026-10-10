# providers/cloudflare/edge

Cloudflare zone settings that long-lived connections depend on: WebSocket proxying on, and Argo Smart Routing off (Cloudflare documents Argo as incompatible with WebSockets). It manages no DNS records and no proxy status.

## When to use it

Use it for a zone that fronts services holding WebSocket connections. You declare the origin paths in `websocket_paths`; while any are declared, a plan that turns WebSockets off is refused.

## Usage

```hcl
module "cloudflare_edge" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/providers/cloudflare/edge?ref=v1.0.0"

  zone_id         = "0123456789abcdef0123456789abcdef"
  websocket_paths = ["/shell/ws"]
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token # Zone Settings:Edit on the zone
}
```

Argo is a paid add-on that does not exist on a Free-plan zone, so it is unmanaged by default (`manage_argo_smart_routing = false`). The module does not set `proxy_read_timeout`, which is Enterprise-only.

To adopt a zone configured by hand, import first: `terraform import 'module.cloudflare_edge.cloudflare_zone_setting.websockets' '<zone_id>/websockets'`, then confirm the plan is empty.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `zone_id` | yes | Cloudflare zone id for the managed apex (e.g, the zone for "example.com"). |
| `websocket_paths` | yes | The origin paths served through this zone that carry WebSocket traffic (e.g, ["/shell/ws", "/terminal"]). |
| `websockets_enabled` | no | Whether the zone proxies WebSocket connections. |
| `manage_argo_smart_routing` | no | Whether Terraform manages the Argo Smart Routing setting at all. |
| `argo_smart_routing_enabled` | no | Whether Argo Smart Routing is enabled. |

Outputs: `websockets_enabled`, `argo_smart_routing_managed`, `websocket_paths`.
