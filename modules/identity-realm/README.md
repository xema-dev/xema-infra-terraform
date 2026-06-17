# `identity-realm`

Cloud-agnostic [`identity-realm`](../../docs/CONTRACTS.md#cloud-agnostic-modules-no-per-cloud-implementation-needed)
module. Declares a **single** Keycloak realm and everything inside it — the realm
settings, OpenID clients, realm roles, and protocol mappers — against the
[`keycloak/keycloak`](https://registry.terraform.io/providers/keycloak/keycloak/latest)
provider (`>= 5.0`).

## This module OWNS the realm declaratively

This module is the **source of truth** for the realm it manages. Everything in
the realm is described as Terraform inputs, so the desired state is whatever this
module declares — drift is reconciled on the next `apply`.

> **Scoped to ONE realm — never master/other realms.** The canonical Xema
> deployment runs on an external, **shared** Keycloak that also hosts non-Xema
> realms. This module manages exactly `var.realm_name` (e.g. `xema-prod`) and its
> children. It declares no provider block and creates no other realm. The
> `realm_name` validation refuses `master`.

> **Supersedes app-side realm reconciliation.** Because this module owns the realm
> declaratively, the platform's in-app realm reconciliation (the boot-time
> realm/client/mapper mutation in `identity-api`) MUST run in **verify/off** mode
> against any realm managed here — otherwise the two writers fight. Terraform is
> the writer; the app verifies, it does not mutate.

## Usage

```hcl
module "identity_realm" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/identity-realm?ref=v0.1.0"

  realm_name   = "xema-prod"
  display_name = "Xema"

  clients = {
    web-app = {
      client_id             = "web-app"
      access_type           = "PUBLIC"
      standard_flow_enabled = true
      valid_redirect_uris   = ["https://app.example.com/*"]
      web_origins           = ["https://app.example.com"]
    }
    identity-api = {
      client_id                = "identity-api"
      access_type              = "CONFIDENTIAL"
      service_accounts_enabled = true
    }
  }

  realm_roles = ["platform_admin", "org_owner", "member"]

  protocol_mappers = {
    org-roles = {
      client           = "web-app"
      user_attribute   = "org_roles"
      claim_name       = "org_roles"
      claim_value_type = "JSON"
      multivalued      = true
    }
  }
}
```

The provider is configured by the **root/stack**, not here (see
[CONVENTIONS.md](../../docs/CONVENTIONS.md)).

## Importing

Per [terraform-provider-keycloak](https://registry.terraform.io/providers/keycloak/keycloak/latest)
import syntax:

- **Realm** — id is the realm **name**:
  ```
  terraform import module.identity_realm.keycloak_realm.this xema-prod
  ```
- **Client** — id is `"<realm>/client/<uuid>"`:
  ```
  terraform import 'module.identity_realm.keycloak_openid_client.this["web-app"]' xema-prod/client/<uuid>
  ```
- **Realm role** — a realm-level role is a `keycloak_role` with no `client_id`;
  id is `"<realm>/<role-name>"`:
  ```
  terraform import 'module.identity_realm.keycloak_role.this["member"]' xema-prod/member
  ```

| Input | Required | Description |
| --- | --- | --- |
| `realm_name` | yes | the single realm owned (never `master`) |
| `display_name`, `enabled`, `ssl_required`, `registration_allowed`, `reset_password_allowed`, `login_with_email_allowed` | no | realm settings |
| `access_token_lifespan`, `sso_session_idle_timeout`, `sso_session_max_lifespan` | no | token/session lifespans (Go duration strings) |
| `clients` | no | OpenID clients keyed by id; `access_type` validated |
| `realm_roles` | no | realm-level roles |
| `protocol_mappers` | no | optional user-attribute → claim mappers (e.g. `org_roles`) |

Outputs: `realm_id`, `client_ids` (map), `client_secrets` (map, **sensitive**).
