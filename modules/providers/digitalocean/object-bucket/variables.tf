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
