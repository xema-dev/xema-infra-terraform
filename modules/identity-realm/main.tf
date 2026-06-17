resource "keycloak_realm" "this" {
  realm        = var.realm_name
  enabled      = var.enabled
  display_name = var.display_name != "" ? var.display_name : var.realm_name

  registration_allowed     = var.registration_allowed
  reset_password_allowed   = var.reset_password_allowed
  login_with_email_allowed = var.login_with_email_allowed
  ssl_required             = var.ssl_required

  access_token_lifespan    = var.access_token_lifespan != "" ? var.access_token_lifespan : null
  sso_session_idle_timeout = var.sso_session_idle_timeout != "" ? var.sso_session_idle_timeout : null
  sso_session_max_lifespan = var.sso_session_max_lifespan != "" ? var.sso_session_max_lifespan : null
}

resource "keycloak_openid_client" "this" {
  for_each = var.clients

  realm_id  = keycloak_realm.this.id
  client_id = each.value.client_id
  name      = each.value.name != "" ? each.value.name : each.value.client_id

  access_type = each.value.access_type

  standard_flow_enabled    = each.value.standard_flow_enabled
  service_accounts_enabled = each.value.service_accounts_enabled

  valid_redirect_uris = each.value.valid_redirect_uris
  web_origins         = each.value.web_origins
}

# A realm-level role is a keycloak_role with no client_id set.
resource "keycloak_role" "this" {
  for_each = var.realm_roles

  realm_id = keycloak_realm.this.id
  name     = each.value
}

resource "keycloak_openid_user_attribute_protocol_mapper" "this" {
  for_each = var.protocol_mappers

  realm_id  = keycloak_realm.this.id
  client_id = keycloak_openid_client.this[each.value.client].id
  name      = each.value.name != "" ? each.value.name : each.key

  user_attribute = each.value.user_attribute
  claim_name     = each.value.claim_name

  claim_value_type    = each.value.claim_value_type
  multivalued         = each.value.multivalued
  add_to_id_token     = each.value.add_to_id_token
  add_to_access_token = each.value.add_to_access_token
  add_to_userinfo     = each.value.add_to_userinfo

  lifecycle {
    precondition {
      condition     = contains(keys(var.clients), each.value.client)
      error_message = "protocol_mappers[\"${each.key}\"].client (\"${each.value.client}\") must reference a key present in var.clients."
    }
  }
}
