variable "name" {
  description = "Globally-unique Spaces bucket name."
  type        = string
}

variable "region" {
  description = <<-EOT
    DO Spaces region slug. Generic — not validated against a fixed list so new DO
    regions work without a module change. Supported at time of writing:
    nyc3, ams3, sgp1, sfo2, sfo3, fra1, syd1, blr1.
  EOT
  type        = string
}

variable "acl" {
  description = "Canned ACL: one of \"private\" or \"public-read\"."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public-read"], var.acl)
    error_message = "acl must be one of private, public-read."
  }
}

variable "versioning" {
  description = "Enable object versioning on the bucket."
  type        = bool
  default     = false
}

variable "cors_rules" {
  description = <<-EOT
    Browser CORS rules, so presigned PUT/GET work straight from a web origin.
    Default [] sets none (today's behaviour). Each rule: allowed_origins ("*" or
    scheme://host[:port], no path), allowed_methods (upper-case, one of GET PUT DELETE POST HEAD),
    allowed_headers, exposed_headers and max_age (preflight cache, whole seconds).
  EOT
  type = list(object({
    allowed_origins = list(string)
    allowed_methods = list(string)
    allowed_headers = optional(list(string), [])
    exposed_headers = optional(list(string), [])
    max_age         = optional(number, 0)
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.cors_rules : length(r.allowed_origins) > 0 && length(r.allowed_methods) > 0])
    error_message = "Each cors_rules entry needs at least one allowed_origins and one allowed_methods."
  }

  validation {
    condition     = alltrue([for r in var.cors_rules : alltrue([for o in r.allowed_origins : o == "*" || can(regex("^https?://[^/]+$", o))])])
    error_message = "Each cors_rules allowed_origins entry must be \"*\" or a scheme://host[:port] origin without a path (e.g. \"https://app.example.com\")."
  }

  validation {
    condition     = alltrue([for r in var.cors_rules : alltrue([for m in r.allowed_methods : contains(["GET", "PUT", "DELETE", "POST", "HEAD"], m)])])
    error_message = "Each cors_rules allowed_methods entry must be upper-case and one of GET PUT DELETE POST HEAD."
  }

  validation {
    condition     = alltrue([for r in var.cors_rules : r.max_age >= 0 && r.max_age == floor(r.max_age)])
    error_message = "cors_rules max_age must be a whole number of seconds >= 0."
  }
}
