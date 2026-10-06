# `identity-realm`

Cloud-agnostic [`identity-realm`](../../docs/CONTRACTS.md#cloud-agnostic-modules-no-per-cloud-implementation-needed)
module. Declares a **single** Keycloak realm and everything inside it — the realm
settings, OpenID clients, realm roles, and protocol mappers — against the
[`keycloak/keycloak`](https://registry.terraform.io/providers/keycloak/keycloak/latest)
provider (`>= 5.0`).

## This module OWNS the realm declaratively

This module manages a realm's **container + identity**, and *optionally* base
client/role/mapper definitions you pass in. It is **NOT** the sole writer of the
realm. In a Xema deployment the realm coexists with `identity-api`, which
**authoritatively reconciles platform-access objects on every boot** (idempotent,
fail-loud). Do **not** double-manage those — it causes a drift war and changes how
`identity-api` works.

> **Scoped to ONE realm — never master/other realms.** A deployment typically
> runs on an external, **shared** Keycloak that also hosts other products'
> realms. This module manages exactly `var.realm_name` (e.g. `acme-prod`). It
> declares no provider block and creates no other realm; the `realm_name`
> validation refuses `master`.

**Terraform owns (safe to declare here):**
- the realm **resource** (existence) + a few identity settings: `display_name`,
  `enabled`, registration/reset/email/ssl flags;
- **identity providers** (SAML/OIDC) — `identity-api` never touches these;
- **base definitions** of clients/roles NOT in identity-api's reconciled set
  (custom clients, custom realm roles), passed via `clients` / `realm_roles`.

**`identity-api` owns — DO NOT put these in `clients`/`realm_roles`/`protocol_mappers`:**
- platform realm roles: `platform_admin`, `platform_support`, `micro-service`,
  `runner*`, the `org_*` taxonomy;
- the `platform-agent-worker` client (created + secret synced on boot);
- the `entitlement` and `scoped-service-claims` client scopes + their protocol
  mappers (`org_roles`, scoped-service claims);
- realm event listeners (`identity-api-provisioner`), realm attributes
  (`identityApiUrl`/`identityApiInternalToken`), the user-profile
  `unmanagedAttributePolicy`, and token lifespans it sets via
  `POST /realms/{id}/configure`.

`identity-api` documents this split itself — its boot path "deliberately does NOT
run applyRealmRoles / applyClients … that an environment's realm import owns."
This module is that realm import for the **container**; leave `identity-api` its
platform-access reconciliation (do not flip it to verify/off for these objects).

> **Rich operational config is `ignore_changes`d.** Themes, SMTP, password policy,
> i18n, and signing crypto are NOT managed here (operator/`identity-api` own them)
> — adopting an existing realm never strips them. See `main.tf`.

**When adopting a realm that `identity-api` already reconciles** it is imported **shell-only**
(`clients`/`realm_roles`/`protocol_mappers` empty) precisely because `identity-api`
owns the platform clients/roles/mappers. Keep them empty unless adding a NEW object
that `identity-api` does not reconcile.

## Usage

```hcl
module "identity_realm" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/identity-realm?ref=v0.12.1"

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
  terraform import module.identity_realm.keycloak_realm.this acme-prod
  ```
- **Client** — id is `"<realm>/client/<uuid>"`:
  ```
  terraform import 'module.identity_realm.keycloak_openid_client.this["web-app"]' acme-prod/client/<uuid>
  ```
- **Realm role** — a realm-level role is a `keycloak_role` with no `client_id`;
  id is `"<realm>/<role-name>"`:
  ```
  terraform import 'module.identity_realm.keycloak_role.this["member"]' acme-prod/member
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
