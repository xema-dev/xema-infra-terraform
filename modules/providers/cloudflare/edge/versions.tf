terraform {
  required_providers {
    cloudflare = {
      # >= 5.0 is REQUIRED, not conservative: `cloudflare_zone_setting` (one
      # resource per setting) is a v5 resource. In v4 the equivalent was the
      # bulk `cloudflare_zone_settings_override`, so a v4 provider fails with
      # "does not support resource type" — verified, not assumed.
      source  = "cloudflare/cloudflare"
      version = ">= 5.0"
    }
  }
}
