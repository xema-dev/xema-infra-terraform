variable "realm_name" {
  description = "The single realm this module owns (e.g. \"acme-prod\"). The module is scoped to exactly this realm and never touches master or any other realm on the shared Keycloak."
  type        = string

  validation {
    condition     = var.realm_name != "master" && length(var.realm_name) > 0
    error_message = "realm_name must be set and must not be \"master\" — this module must never manage the master realm."
  }
}

variable "display_name" {
  description = "Human-readable realm display name shown on login screens."
  type        = string
  default     = ""
}

variable "enabled" {
  description = "Whether the realm is enabled."
  type        = bool
  default     = true
}

variable "registration_allowed" {
  description = "Whether self-registration is allowed on the realm."
  type        = bool
  default     = false
}

variable "reset_password_allowed" {
  description = "Whether the realm exposes the \"forgot password\" flow."
  type        = bool
  default     = true
}

variable "login_with_email_allowed" {
  description = "Whether users may log in with their email address."
  type        = bool
  default     = true
}

variable "ssl_required" {
  description = "SSL enforcement for the realm. One of \"all\", \"external\", or \"none\"."
  type        = string
  default     = "external"

  validation {
    condition     = contains(["all", "external", "none"], var.ssl_required)
    error_message = "ssl_required must be one of all, external, none."
  }
}

variable "access_token_lifespan" {
  description = "Access token lifespan as a Go duration string (e.g. \"5m\"). Empty string keeps the Keycloak default."
  type        = string
  default     = ""
}

variable "sso_session_idle_timeout" {
  description = "SSO session idle timeout as a Go duration string (e.g. \"30m\"). Empty string keeps the Keycloak default."
  type        = string
  default     = ""
}

variable "sso_session_max_lifespan" {
  description = "SSO session max lifespan as a Go duration string (e.g. \"10h\"). Empty string keeps the Keycloak default."
  type        = string
  default     = ""
}

variable "clients" {
  description = <<-EOT
    OpenID clients to create in the realm, keyed by a stable id. Each client:
      - client_id                : the OIDC client_id
      - access_type              : one of CONFIDENTIAL | PUBLIC | BEARER-ONLY
      - standard_flow_enabled    : enable the authorization-code flow
      - service_accounts_enabled : enable the service-account (client-credentials) grant (CONFIDENTIAL only)
      - valid_redirect_uris      : allowed redirect URIs
      - web_origins              : allowed CORS web origins
      - name                     : optional human-readable name
  EOT
  type = map(object({
    client_id                = string
    access_type              = string
    standard_flow_enabled    = optional(bool, true)
    service_accounts_enabled = optional(bool, false)
    valid_redirect_uris      = optional(list(string), [])
    web_origins              = optional(list(string), [])
    name                     = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for c in values(var.clients) :
      contains(["CONFIDENTIAL", "PUBLIC", "BEARER-ONLY"], c.access_type)
    ])
    error_message = "Each client access_type must be one of CONFIDENTIAL, PUBLIC, BEARER-ONLY."
  }

  validation {
    condition = alltrue([
      for c in values(var.clients) :
      c.access_type == "CONFIDENTIAL" || c.service_accounts_enabled == false
    ])
    error_message = "service_accounts_enabled requires access_type CONFIDENTIAL."
  }
}

variable "realm_roles" {
  description = "Realm-level roles to create."
  type        = set(string)
  default     = []
}

variable "protocol_mappers" {
  description = <<-EOT
    Optional per-client user-attribute → token-claim protocol mappers, keyed by a
    stable id. Used for claims the platform needs (e.g. org_roles / attributes).
    Each mapper:
      - client           : key into var.clients identifying the owning client
      - user_attribute   : the Keycloak user attribute to read
      - claim_name       : the token claim to write
      - claim_value_type : one of String | long | int | boolean | JSON
      - name             : optional mapper name (defaults to the map key)
      - add_to_id_token / add_to_access_token / add_to_userinfo : token placement
      - multivalued      : emit the claim as a JSON array
  EOT
  type = map(object({
    client              = string
    user_attribute      = string
    claim_name          = string
    claim_value_type    = optional(string, "String")
    name                = optional(string, "")
    add_to_id_token     = optional(bool, true)
    add_to_access_token = optional(bool, true)
    add_to_userinfo     = optional(bool, true)
    multivalued         = optional(bool, false)
  }))
  default = {}

  validation {
    condition = alltrue([
      for m in values(var.protocol_mappers) :
      contains(["String", "long", "int", "boolean", "JSON"], m.claim_value_type)
    ])
    error_message = "Each protocol mapper claim_value_type must be one of String, long, int, boolean, JSON."
  }
}
