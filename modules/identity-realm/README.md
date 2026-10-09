# identity-realm

Declares one Keycloak realm, with its settings, OpenID clients, realm roles and protocol mappers, using the [`keycloak/keycloak`](https://registry.terraform.io/providers/keycloak/keycloak/latest) provider (`>= 5.0`).

## When to use it

Use it to create or adopt the realm container for a deployment. It manages exactly `realm_name` and refuses `master`. It is not the only writer of the realm: `identity-api` reconciles platform roles, the platform clients and their scopes and mappers on every boot, so leave those out of `clients`, `realm_roles` and `protocol_mappers`. Themes, SMTP, password policy and signing keys are not managed here.

## Usage

```hcl
module "identity_realm" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/identity-realm?ref=v0.13.0"

  realm_name   = "acme-prod"
  display_name = "Acme"

  clients = {
    web-app = {
      client_id             = "web-app"
      access_type           = "PUBLIC"
      standard_flow_enabled = true
      valid_redirect_uris   = ["https://app.example.com/*"]
      web_origins           = ["https://app.example.com"]
    }
  }
}
```

The `keycloak` provider is configured by the root. Import ids: the realm name, `<realm>/client/<uuid>` for a client, `<realm>/<role-name>` for a realm role.

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `realm_name` | yes | The single realm this module owns (e.g, "acme-prod"). |
| `display_name` | no | Human-readable realm display name shown on login screens (realm shell). |
| `enabled` | no | Whether the realm is enabled (realm shell). All realm policy (login flags, token and session lifespans, SSL requirement) is owned by identity-api. |
| `clients` | no | OpenID clients to create in the realm, keyed by a stable id. |
| `realm_roles` | no | Realm-level roles to create. |
| `protocol_mappers` | no | Optional per-client user-attribute → token-claim protocol mappers, keyed by a stable id. |

Outputs: `realm_id`, `client_ids`, `client_secrets`.
