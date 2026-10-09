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
